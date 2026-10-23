import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import image from '@ohos.multimedia.image';
import { LocalBookService } from '../../core/book/LocalBookService';
import { ReaderImageMarker } from '../../core/book/ReaderImageMarker';
import { ReaderImageResults } from '../../core/book/ReaderImageResults';
import { ReaderContinuousDataSource, ReaderScrollItem } from '../../core/reader/ReaderDataSources';
import { ReaderComicSuperResolution } from '../../core/reader/ReaderComicSuperResolution';
import { ComicChineseConverter } from '../../core/reader/ComicChineseConverter';
import { ComicTextLayer, ComicTextPatch } from '../../core/reader/ComicTextTypes';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/** 图片宽高比缓存与本地文件尺寸探测，漫画视图和小说滚动模式里的整页插图共用。 */
export class ReaderComicImageSizes {
  private static readonly LIMIT: number = 2048;
  /** source -> 高/宽。 */
  private static readonly ratios: Map<string, number> = new Map<string, number>();
  private static readonly probing: Set<string> = new Set<string>();

  static ratio(source: string): number {
    return ReaderComicImageSizes.ratios.get(source) || 0;
  }

  static remember(source: string, width: number, height: number): number {
    if (!source || width <= 0 || height <= 0) return 0;
    const ratio = height / width;
    if (!Number.isFinite(ratio) || ratio <= 0) return 0;
    if (ReaderComicImageSizes.ratios.size >= ReaderComicImageSizes.LIMIT) {
      const oldest = ReaderComicImageSizes.ratios.keys().next().value as string | undefined;
      if (oldest !== undefined) ReaderComicImageSizes.ratios.delete(oldest);
    }
    ReaderComicImageSizes.ratios.set(source, ratio);
    return ratio;
  }

  /** 不是本地文件（网络地址或内嵌 data: 数据），不能按文件探测尺寸。 */
  static isRemote(source: string): boolean {
    return /^(?:https?:|data:)/i.test(source || '');
  }

  /** 真正要走网络的地址；data: 内嵌数据不算，出错时不能提示成网络问题。 */
  static isNetwork(source: string): boolean {
    return /^https?:/i.test(source || '');
  }

  static uri(source: string): string {
    if (!source || ReaderImageMarker.failureReason(source) || ReaderImageMarker.pendingRaw(source)) return '';
    if (/^(?:https?:|data:|file:)/i.test(source)) return source;
    try {
      return fileUri.getUriFromPath(source);
    } catch (_) {
      return source;
    }
  }

  /** 读取本地图片头信息得到宽高比；远程图片和读取失败返回 0。 */
  static async probe(source: string): Promise<number> {
    const cached = ReaderComicImageSizes.ratio(source);
    if (cached > 0) return cached;
    if (!source || ReaderComicImageSizes.isRemote(source) || ReaderComicImageSizes.probing.has(source)) return 0;
    let path = source;
    if (/^file:/i.test(path)) {
      try {
        path = new fileUri.FileUri(path).path;
      } catch (_) {
        return 0;
      }
    }
    ReaderComicImageSizes.probing.add(source);
    let file: fs.File | null = null;
    let imageSource: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(file.fd);
      const info = await imageSource.getImageInfo();
      return ReaderComicImageSizes.remember(source, info.size.width, info.size.height);
    } catch (_) {
      return 0;
    } finally {
      ReaderComicImageSizes.probing.delete(source);
      if (imageSource) {
        try {
          await imageSource.release();
        } catch (_) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }
}

/** 失败图片的重试入口：图片项挂载时登记，视图按点击位置找到对应项后调用。 */
export class ReaderComicRetryRegistry {
  private readonly handlers: Map<string, () => void> = new Map<string, () => void>();
  private readonly reloaders: Map<string, () => void> = new Map<string, () => void>();

  register(key: string, handler: () => void): void {
    this.handlers.set(key, handler);
  }

  unregister(key: string, handler: () => void): void {
    if (this.handlers.get(key) === handler) this.handlers.delete(key);
  }

  registerReload(key: string, handler: () => void): void {
    this.reloaders.set(key, handler);
  }

  unregisterReload(key: string, handler: () => void): void {
    if (this.reloaders.get(key) === handler) this.reloaders.delete(key);
  }

  /** 不论成功与否重新加载这一项（长按菜单“重新加载”）。 */
  reload(key: string): void {
    const handler = this.reloaders.get(key);
    if (handler) handler();
  }

  /** 该项处于失败状态时重试并返回 true。 */
  retry(key: string): boolean {
    const handler = this.handlers.get(key);
    if (!handler) return false;
    handler();
    return true;
  }
}

/**
 * 一张整页图片。比例未知时先用接近屏宽的短占位，拿到比例后严格按比例给出高度，
 * 每项自己持有比例和失败状态，不需要外部通知列表刷新。
 */
@Component
export struct ReaderComicImageItem {
  @Prop @Watch('onMarkerChanged') marker: string = '';
  @Prop viewWidth: number = 0;
  @Prop viewHeight: number = 0;
  /** 整张图放进一屏（条漫的“适应屏幕”）。 */
  @Prop fitScreen: boolean = false;
  /** 与上一张图片相接时向上多画 1px，避免两项各自取整后露出底色细缝。 */
  @Prop seamOverlap: boolean = false;
  /** 大于 0 时进入翻页模式：整张图等比放进 boxWidth × boxHeight 的框里，不按比例撑高。 */
  @Prop boxWidth: number = 0;
  @Prop boxHeight: number = 0;
  /** 加载中占位里显示的页码，空串不显示。 */
  @Prop pageLabel: string = '';
  @Prop hintColor: string = '#99FFFFFF';
  /** 失败图片登记重试入口用的键；为空时失败提示自身响应点击。 */
  @Prop retryKey: string = '';
  /** 在屏幕上时用端侧超分替换低清原图（会员功能，调用方已判断权限）。 */
  @Prop @Watch('onSuperResolutionChanged') superResolution: boolean = false;
  /** 在屏幕上时识别图中文字，把繁体改写成简体叠在图上（调用方已判断系统能力）。 */
  @Prop @Watch('onTextConvertChanged') textConvert: boolean = false;
  retryRegistry: ReaderComicRetryRegistry | null = null;
  /** 服务器拒绝了这张图（多为签名地址过期）。 */
  onDenied: () => void = () => {};
  @State private ratio: number = 0;
  @State private loaded: boolean = false;
  @State private broken: boolean = false;
  @State private loadToken: number = 0;
  /** 服务器拒绝（401/403），多为签名地址过期，重试无用，需要重新抓取本章。 */
  @State private denied: boolean = false;
  /** 正文获取时这张图已下载/解密失败：只显示原因，不再加载。 */
  @State private failure: string = '';
  /** 超分结果地址；叠在原图上，解码完成后淡入，原图留在下面兜底。 */
  @State private enhancedUri: string = '';
  @State private enhancedShown: boolean = false;
  /** 刚换成超分图时在角上短暂提示一下。 */
  @State private enhancedBadge: boolean = false;
  /** 繁→简文字层，坐标按原图像素；叠在原图和超分图之上。 */
  @State private textPatches: ComicTextPatch[] = [];
  @State private textImageWidth: number = 0;
  @State private textImageHeight: number = 0;
  private textTicket: number = 0;
  private textAttempted: boolean = false;
  private visible: boolean = false;
  /** 每次重置加一，旧任务的结果作废。 */
  private enhanceTicket: number = 0;
  private enhanceAttempted: boolean = false;
  /** 当前显示的图片来源；渐进加载还没有结果时为空串，显示加载占位。 */
  @State private source: string = '';
  /** 渐进加载的图片的原始值，订阅 ReaderImageResults 等结果；不是渐进加载时为空串。 */
  private pendingRaw: string = '';
  private unsubscribePending: (() => void) | null = null;
  /** 已向 ReaderImageResults 登记为屏幕上正等着的图片。 */
  private pendingVisibleMarked: boolean = false;
  /** 已登记为屏幕附近的图片：条漫列表只挂载可见区及其缓存项，挂载着就说明马上可能看到。 */
  private pendingNearMarked: boolean = false;
  private registeredRetryKey: string = '';
  private readonly retryHandler: () => void = (): void => this.retry();
  private readonly reloadHandler: () => void = (): void => this.reload();
  private registeredReloadKey: string = '';

  aboutToAppear(): void {
    this.resetForMarker();
    if (this.retryKey && this.retryRegistry) {
      this.registeredReloadKey = this.retryKey;
      this.retryRegistry.registerReload(this.retryKey, this.reloadHandler);
    }
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.releasePending();
    this.enhanceTicket++;
    this.textTicket++;
    this.unregisterRetry();
    if (this.registeredReloadKey && this.retryRegistry) {
      this.retryRegistry.unregisterReload(this.registeredReloadKey, this.reloadHandler);
    }
  }

  /** 长按保存/分享的兜底截取用的组件 id。 */
  static snapshotId(key: string): string {
    return `reader_comic_image_${key}`;
  }

  private reload(): void {
    this.broken = false;
    this.denied = false;
    this.loaded = false;
    this.resetEnhancement();
    this.resetTextLayer();
    this.unregisterRetry();
    this.loadToken++;
  }

  onSuperResolutionChanged(): void {
    this.resetEnhancement();
    this.maybeEnhance();
  }

  private resetEnhancement(): void {
    this.enhanceTicket++;
    this.enhanceAttempted = false;
    this.enhancedUri = '';
    this.enhancedShown = false;
    this.enhancedBadge = false;
  }

  onTextConvertChanged(): void {
    this.resetTextLayer();
    this.maybeConvertText();
  }

  private resetTextLayer(): void {
    this.textTicket++;
    this.textAttempted = false;
    this.textPatches = [];
    this.textImageWidth = 0;
    this.textImageHeight = 0;
  }

  /** 原图显示出来且在屏幕上时排队识别，每张图只试一次；识别不了或没有可改写的字就保持原图。 */
  private maybeConvertText(): void {
    if (!this.textConvert || !this.visible || !this.loaded || this.broken || this.failure ||
      this.textAttempted || this.ratio <= 0 || !this.source) return;
    this.textAttempted = true;
    const ticket = ++this.textTicket;
    const active = (): boolean => this.visible && this.textConvert && ticket === this.textTicket;
    ComicChineseConverter.layer(getContext(this), this.source, active).then((layer: ComicTextLayer): void => {
      if (ticket !== this.textTicket || !this.textConvert || layer.imageWidth <= 0 || layer.imageHeight <= 0) return;
      this.textImageWidth = layer.imageWidth;
      this.textImageHeight = layer.imageHeight;
      this.textPatches = layer.patches;
    }).catch((error: Error): void => {
      if (ticket === this.textTicket && error?.message) console.warn(`[ComicText] 繁→简未完成: ${error.message}`);
    });
  }

  /** 图片实际显示高度（vp）。 */
  private displayHeight(): number {
    if (!this.boxed()) return this.imageHeight();
    return this.ratio > 0 ? this.displayWidth() * this.ratio : this.boxHeight;
  }

  private showEnhancedBadge(): void {
    if (this.enhancedShown) return;
    this.enhancedShown = true;
    this.enhancedBadge = true;
    const ticket = this.enhanceTicket;
    setTimeout(() => {
      if (ticket === this.enhanceTicket) this.enhancedBadge = false;
    }, 1600);
  }

  /** 原图显示出来、比例已知且在屏幕上时排队超分，每张图只试一次。 */
  private maybeEnhance(): void {
    if (!this.superResolution || !this.visible || !this.loaded || this.broken || this.failure ||
      this.enhanceAttempted || this.ratio <= 0 || !this.source) return;
    this.enhanceAttempted = true;
    const ticket = ++this.enhanceTicket;
    const source = this.source;
    const active = (): boolean => this.visible && this.superResolution && ticket === this.enhanceTicket;
    ReaderComicSuperResolution.enhance(source, vp2px(this.displayWidth()), active).then((uri: string): void => {
      if (uri && ticket === this.enhanceTicket && this.superResolution) this.enhancedUri = uri;
    }).catch((_: Error): void => {
    });
  }

  /** 图片实际显示宽度（vp）。 */
  private displayWidth(): number {
    if (!this.boxed()) return this.imageWidth();
    return this.ratio > 0 ? Math.min(this.boxWidth, this.boxHeight / this.ratio) : this.boxWidth;
  }

  onMarkerChanged(): void {
    this.resetForMarker();
  }

  private resetForMarker(): void {
    this.releasePending();
    const info = ReaderImageMarker.parse(this.marker);
    const raw = ReaderImageMarker.pendingRaw(info.source);
    if (!raw) {
      this.applySource(info.source, info.width, info.height);
      return;
    }
    this.pendingRaw = raw;
    let resolved = ReaderImageResults.current(raw);
    // 登记已被清理、或处理被取消：再也等不到结果，按失败提示刷新本章。
    if (!resolved && !ReaderImageResults.isAlive(raw)) resolved = ReaderImageMarker.failureSource('图片加载已中断');
    if (resolved) {
      this.applySource(resolved, info.width, info.height);
      return;
    }
    this.applySource('', info.width, info.height);
    this.unsubscribePending = ReaderImageResults.subscribe(raw, (source: string): void => {
      if (raw !== this.pendingRaw) return;
      this.applySource(source, info.width, info.height);
      this.loadToken++;
      this.syncPendingVisible();
    });
    ReaderImageResults.setNear(raw, true);
    this.pendingNearMarked = true;
    this.syncPendingVisible();
  }

  private releasePending(): void {
    if (this.unsubscribePending) this.unsubscribePending();
    this.unsubscribePending = null;
    if (this.pendingVisibleMarked) ReaderImageResults.setVisible(this.pendingRaw, false);
    this.pendingVisibleMarked = false;
    if (this.pendingNearMarked) ReaderImageResults.setNear(this.pendingRaw, false);
    this.pendingNearMarked = false;
    this.pendingRaw = '';
  }

  /** 渐进加载还没结果的图片在屏幕上时登记为可见，调度时排在最前。 */
  private syncPendingVisible(): void {
    const marked = this.visible && !!this.pendingRaw && !this.source;
    if (marked === this.pendingVisibleMarked) return;
    this.pendingVisibleMarked = marked;
    ReaderImageResults.setVisible(this.pendingRaw, marked);
  }

  private applySource(source: string, width: number, height: number): void {
    this.source = source;
    this.failure = ReaderImageMarker.failureReason(source);
    this.loaded = false;
    this.broken = false;
    this.denied = false;
    this.resetEnhancement();
    this.resetTextLayer();
    this.unregisterRetry();
    if (this.failure) {
      this.ratio = 0;
      return;
    }
    let ratio = width > 0 && height > 0 ? height / width : 0;
    if (ratio <= 0) ratio = ReaderComicImageSizes.ratio(this.source);
    this.ratio = ratio;
    if (ratio > 0 || !this.source || ReaderComicImageSizes.isRemote(this.source)) return;
    const expected = this.source;
    ReaderComicImageSizes.probe(expected).then((probed: number): void => {
      if (probed > 0 && expected === this.source && this.ratio <= 0) this.ratio = probed;
    }).catch((_: Error): void => {
    });
  }

  private retry(): void {
    if (!this.broken) return;
    this.broken = false;
    this.loaded = false;
    this.unregisterRetry();
    this.loadToken++;
  }

  private unregisterRetry(): void {
    if (this.registeredRetryKey && this.retryRegistry) {
      this.retryRegistry.unregister(this.registeredRetryKey, this.retryHandler);
    }
    this.registeredRetryKey = '';
  }

  private markBroken(error: ImageError): void {
    if (this.broken) return;
    this.broken = true;
    this.denied = /\b40[13]\b/.test(error?.message || '');
    if (this.denied) this.onDenied();
    if (this.retryKey && this.retryRegistry) {
      this.registeredRetryKey = this.retryKey;
      this.retryRegistry.register(this.retryKey, this.retryHandler);
    }
    const remote = ReaderComicImageSizes.isRemote(this.source);
    const origin = ReaderComicImageSizes.isNetwork(this.source) ? '网络' : (remote ? '内嵌数据' : '本地');
    let exists = false;
    if (!remote && this.source) {
      try {
        exists = fs.accessSync(this.source);
      } catch (_) {
        exists = false;
      }
    }
    console.error(`[ReaderComic] 图片加载失败 来源=${origin} 文件存在=${exists} ` +
      `message=${error?.message || ''} 路径=${remote ? this.source.substring(0, 160) : this.source}`);
  }

  private imageWidth(): number {
    const width = Math.max(1, this.viewWidth);
    if (!this.fitScreen || this.ratio <= 0 || this.viewHeight <= 0) return width;
    return Math.min(width, this.viewHeight / this.ratio);
  }

  private imageHeight(): number {
    // 尺寸未知时使用接近图片宽度的短占位，避免解码失败时每张图片都遗留整屏空白。
    if (this.ratio <= 0 || this.viewWidth <= 0) return Math.max(240, this.viewWidth);
    const height = Math.max(120, Math.min(24000, this.imageWidth() * this.ratio));
    // ListItem 会分别把浮点 vp 高度转换为物理像素；先对齐到整数像素，避免相邻项反向取整后露底。
    return px2vp(Math.max(1, Math.round(vp2px(height))));
  }

  private overlap(): number {
    return this.seamOverlap && !this.boxed() ? px2vp(1) : 0;
  }

  private boxed(): boolean {
    return this.boxWidth > 0 && this.boxHeight > 0;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.failure) {
        Column({ space: AppSpacing.SM }) {
          Text('⚠ 图片未能显示')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.hintColor)
          Text(this.failure)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.hintColor)
            .opacity(0.8)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
          Text('点右上角刷新本章可重新获取')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.hintColor)
            .opacity(0.6)
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .hitTestBehavior(HitTestMode.None)
      } else {
        ForEach(this.source ? [this.loadToken] : [], (_token: number) => {
          Image(ReaderComicImageSizes.uri(this.source))
            .width(this.boxed() ? '100%' : this.imageWidth())
            .height(this.boxed() ? '100%' : this.imageHeight() + this.overlap())
            // 原图比例尚未返回时保持 Contain；比例已知后容器严格等比，Fill 只消除边缘 letterbox。
            .objectFit(this.boxed() || this.ratio <= 0 ? ImageFit.Contain : ImageFit.Fill)
            .draggable(false)
            .onComplete((event) => {
              if (!event) return;
              if (event.width > 0 && event.height > 0) {
                const ratio = ReaderComicImageSizes.remember(this.source, event.width, event.height);
                if (ratio > 0 && Math.abs(ratio - this.ratio) >= 0.0001) this.ratio = ratio;
                this.loaded = true;
                this.maybeEnhance();
                this.maybeConvertText();
              }
            })
            .onError((error: ImageError) => this.markBroken(error))
            .id(this.retryKey ? ReaderComicImageItem.snapshotId(this.retryKey) : '')
        }, (token: number) => `${token}`)

        if (this.enhancedUri && this.loaded && !this.broken) {
          Image(this.enhancedUri)
            .width(this.boxed() ? '100%' : this.imageWidth())
            .height(this.boxed() ? '100%' : this.imageHeight() + this.overlap())
            .objectFit(this.boxed() ? ImageFit.Contain : ImageFit.Fill)
            .draggable(false)
            .opacity(this.enhancedShown ? 1 : 0)
            .animation({ duration: 220, curve: Curve.EaseOut })
            .hitTestBehavior(HitTestMode.None)
            .onComplete((event) => {
              if (event && event.width > 0 && event.height > 0) this.showEnhancedBadge();
            })
            .onError((_: ImageError) => {
              this.enhancedUri = '';
              this.enhancedShown = false;
            })

          Text('AI 超分')
            .fontSize(AppFontSize.CAPTION)
            .fontColor('#FFFFFF')
            .backgroundColor('#99000000')
            .borderRadius(10)
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 2, bottom: 2 })
            .position({ x: '100%', y: 0 })
            .markAnchor({ x: '100%', y: 0 })
            .translate({ x: -AppSpacing.SM, y: AppSpacing.SM })
            .opacity(this.enhancedBadge ? 1 : 0)
            .animation({ duration: 300, curve: Curve.EaseOut })
            .hitTestBehavior(HitTestMode.None)
        }

        if (this.textPatches.length > 0 && this.loaded && !this.broken) {
          this.textLayerOverlay()
        }

        if (this.broken) {
          Column({ space: AppSpacing.SM }) {
            Text('⚠ 图片加载失败')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.hintColor)
            Text(this.denied ? '图片地址已失效，请点右上角刷新本章' :
              (ReaderComicImageSizes.isNetwork(this.source) ? '网络图片加载失败，点击重试' :
                (ReaderComicImageSizes.isRemote(this.source) ? '内嵌图片数据无法解码，不是支持的图片格式' :
                  '文件可能已被移动、删除或尚未重新导入')))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.hintColor)
              .opacity(0.8)
          }
          .width('100%')
          .onClick(() => this.retry())
        } else if (!this.loaded) {
          Column({ space: AppSpacing.MD }) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(this.hintColor)
            if (this.pageLabel) {
              Text(this.pageLabel)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.hintColor)
            }
          }
          .hitTestBehavior(HitTestMode.None)
        }
      }
    }
    .width(this.boxed() ? this.boxWidth : '100%')
    .height(this.boxed() ? this.boxHeight : this.imageHeight() + this.overlap())
    .margin({ top: -this.overlap() })
    .onVisibleAreaChange([0, 0.01], (isVisible: boolean, ratio: number) => {
      const visible = isVisible && ratio > 0;
      if (visible === this.visible) return;
      this.visible = visible;
      this.syncPendingVisible();
      if (visible) {
        this.maybeEnhance();
        this.maybeConvertText();
      } else {
        // 没等到结果就划走：作废排队的任务，下次出现再排。
        if (!this.enhancedUri && this.enhanceAttempted) {
          this.enhanceTicket++;
          this.enhanceAttempted = false;
        }
        if (this.textImageWidth <= 0 && this.textAttempted) {
          this.textTicket++;
          this.textAttempted = false;
        }
      }
    })
  }

  /** 与图片显示区域等大的文字层；每块用原底色盖住原字，再按原字方向、颜色写简体。 */
  @Builder
  textLayerOverlay() {
    Stack() {
      ForEach(this.textPatches, (patch: ComicTextPatch) => {
        Text(patch.text)
          .position({ x: patch.x * this.textScaleX(), y: patch.y * this.textScaleY() })
          .width(patch.width * this.textScaleX())
          .height(patch.height * this.textScaleY())
          .fontSize(`${patch.fontSize * this.textScaleX()}vp`)
          .maxFontSize(`${patch.fontSize * this.textScaleX()}vp`)
          .minFontSize(`${patch.fontSize * this.textScaleX() * 0.6}vp`)
          .maxLines(patch.lines)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.LAYOUT_CONSTRAINT_FIRST)
          .lineHeight(`${patch.lineHeight * this.textScaleY()}vp`)
          .textOverflow({ overflow: TextOverflow.Clip })
          .textAlign(TextAlign.Center)
          .align(Alignment.Center)
          .fontWeight(FontWeight.Medium)
          .fontColor(patch.color)
          .backgroundColor(patch.background)
          .padding(0)
      }, (patch: ComicTextPatch) => patch.id)
    }
    .width(this.displayWidth())
    .height(this.displayHeight())
    .hitTestBehavior(HitTestMode.None)
  }

  private textScaleX(): number {
    return this.textImageWidth > 0 ? this.displayWidth() / this.textImageWidth : 0;
  }

  private textScaleY(): number {
    return this.textImageHeight > 0 ? this.displayHeight() / this.textImageHeight : 0;
  }
}

/**
 * 不显示任何内容，只在挂载期间把一张渐进加载的图片登记为屏幕附近，让它先于本章其余图片处理。
 * 翻页模式用它覆盖当前跨页之后要预加载的几页。
 */
@Component
export struct ReaderPendingImageHint {
  @Prop raw: string = '';
  private marked: string = '';

  aboutToAppear(): void {
    this.marked = this.raw;
    if (this.marked) ReaderImageResults.setNear(this.marked, true);
  }

  aboutToDisappear(): void {
    if (this.marked) ReaderImageResults.setNear(this.marked, false);
    this.marked = '';
  }

  build() {
    Stack()
      .width(0)
      .height(0)
      .hitTestBehavior(HitTestMode.None)
  }
}

/** 角落信息条：话名、本章页码、时间、电量。 */
@Component
export struct ReaderComicInfoBadge {
  @Prop chapterText: string = '';
  @Prop pageText: string = '';
  @Prop timeText: string = '';
  /** 小于 0 时不画电池。 */
  @Prop battery: number = -1;

  build() {
    Row({ space: AppSpacing.MD }) {
      if (this.chapterText) {
        Text(this.chapterText)
          .fontSize(AppFontSize.MICRO + 1)
          .fontColor('#E6FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 150 })
      }
      if (this.pageText) {
        Text(this.pageText)
          .fontSize(AppFontSize.MICRO + 1)
          .fontColor('#E6FFFFFF')
          .fontFeature('"tnum" on')
      }
      if (this.timeText) {
        Text(this.timeText)
          .fontSize(AppFontSize.MICRO + 1)
          .fontColor('#E6FFFFFF')
          .fontFeature('"tnum" on')
      }
      if (this.battery >= 0) {
        Row() {
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width(`${Math.max(0, Math.min(100, this.battery))}%`)
              .height('100%')
              .backgroundColor('#E6FFFFFF')
              .borderRadius(1)
          }
          .width(17)
          .height(8)
          .padding(1)
          .border({ width: 1, color: '#E6FFFFFF', radius: 2.5 })

          Row()
            .width(1.5)
            .height(3.5)
            .backgroundColor('#E6FFFFFF')
            .borderRadius({ topRight: 1, bottomRight: 1 })
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 3, bottom: 3 })
    .borderRadius(10)
    .backgroundColor('#8C000000')
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }
}

/**
 * 条漫视图：整章图片上下相接。滚动、章节边界拉动和点击都经由覆盖在列表上的交互层，
 * 由阅读页决定点击是翻屏还是呼出菜单；滚动器和数据源归阅读页所有，进度恢复直接操作它们。
 */
@Component
export struct ReaderComicView {
  scroller: ListScroller = new ListScroller();
  dataSource: ReaderContinuousDataSource = new ReaderContinuousDataSource();
  /** 网络图片向后预先加载的张数（列表在视口外预先构建的项数）。 */
  @Prop preloadCount: number = 2;
  /** 长按图片：source 为图片地址，reload 让这一项重新加载。 */
  /** 长按图片：source 为图片地址，reload 让这一项重新加载，snapshotId 是这张图的组件 id。 */
  onImageLongPress: (source: string, reload: () => void, snapshotId: string) => void = () => {};
  /** 某章的图片被服务器拒绝（多为签名地址过期）。 */
  onImageDenied: (chapterIndex: number) => void = () => {};
  /** 章节标题，用于章节之间的分隔卡。 */
  chapterTitle: (chapterIndex: number) => string = () => '';
  @Prop @Watch('onViewportChanged') viewWidth: number = 0;
  @Prop viewHeight: number = 0;
  /** 双击放大/还原。关闭后单击不必等待双击判定，响应更快；双指缩放始终可用。 */
  @Prop doubleTapZoom: boolean = true;
  /** 漫画超分（会员功能）。 */
  @Prop superResolution: boolean = false;
  @Prop textConvert: boolean = false;
  @Prop surfaceColor: string = '#000000';
  @Prop textColor: string = '#E6E6E6';
  @Prop hintColor: string = '#99FFFFFF';
  @Prop pageGap: number = 0;
  @Prop fitScreen: boolean = false;
  /** 关闭时移除交互层，列表按原生方式滚动（加载、切章过程中使用）。 */
  @Prop interactive: boolean = true;
  @Prop panDistance: number = 12;
  @Prop transitionY: number = 0;
  @Prop transitionOpacity: number = 1;
  /** 信息条画在交互层下面：盖在视图上方的任何铺满容器都会截走点击和拖动。 */
  @Prop infoVisible: boolean = false;
  @Prop infoChapter: string = '';
  @Prop infoPage: string = '';
  @Prop infoTime: string = '';
  @Prop infoBattery: number = -1;
  @Prop infoBottomInset: number = 6;
  onVisibleRangeChange: (start: number, end: number) => void = () => {};
  onReachEnd: () => void = () => {};
  onListAppear: () => void = () => {};
  /** 坐标相对视图左上角。 */
  onTap: (x: number, y: number, width: number, height: number) => void = () => {};
  onPanStart: () => void = () => {};
  onPanUpdate: (event: GestureEvent) => void = () => {};
  onPanEnd: (event: GestureEvent) => void = () => {};
  onPanCancel: () => void = () => {};
  /** 缩放倍数变化（1 为未缩放），阅读页据此把“翻一屏”换算成列表内的距离。 */
  onZoomChanged: (scale: number) => void = () => {};
  private retryRegistry: ReaderComicRetryRegistry = new ReaderComicRetryRegistry();
  static readonly MAX_ZOOM: number = 4;
  static readonly DOUBLE_TAP_ZOOM: number = 2;
  // 缩放以视图中心为基点作用在列表上，平移在缩放之后叠加：屏幕点 = 中心 + 倍数 × (列表点 − 中心) + 平移。
  @State private zoomScale: number = 1;
  @State private zoomX: number = 0;
  @State private zoomY: number = 0;
  private reportedZoom: number = 1;
  private pinching: boolean = false;
  private pinchBaseScale: number = 1;
  private pinchBaseX: number = 0;
  private pinchBaseY: number = 0;
  private pinchFocusX: number = 0;
  private pinchFocusY: number = 0;
  private panInProgress: boolean = false;
  /** 本次拖动由缩放平移处理，不交给阅读页（阅读页的拖动带章节边界拉动）。 */
  private zoomPanActive: boolean = false;
  private panLastX: number = 0;
  private panLastY: number = 0;
  private panResync: boolean = false;
  /** 本次触摸已经开始拖动；松手时不能再当作点击处理。 */
  private touchDragged: boolean = false;

  private isImagePage(page: string): boolean {
    return LocalBookService.isEpubImageMarker((page || '').trim());
  }

  private seamOverlap(index: number): boolean {
    const previous = this.dataSource.getData(index - 1);
    return this.pageGap <= 0 && index > 0 && previous.isPage() && this.isImagePage(previous.text);
  }

  onViewportChanged(): void {
    this.resetZoom(false);
  }

  private zoomed(): boolean {
    return this.zoomScale > 1.001;
  }

  private centerX(): number {
    return Math.max(1, this.viewWidth) / 2;
  }

  private centerY(): number {
    return Math.max(1, this.viewHeight) / 2;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private applyZoom(scale: number, x: number, y: number): void {
    let nextScale = this.clamp(scale, 1, ReaderComicView.MAX_ZOOM);
    if (nextScale <= 1.001) nextScale = 1;
    const boundX = (nextScale - 1) * this.centerX();
    const boundY = (nextScale - 1) * this.centerY();
    this.zoomScale = nextScale;
    this.zoomX = this.clamp(x, -boundX, boundX);
    this.zoomY = this.clamp(y, -boundY, boundY);
    if (Math.abs(this.reportedZoom - nextScale) > 0.001) {
      this.reportedZoom = nextScale;
      this.onZoomChanged(nextScale);
    }
  }

  /** 把缩放前位于 origin 的点放到 focus 处，同时从 base 状态缩放到 nextScale（双指移动时兼作平移）。 */
  private zoomAround(focusX: number, focusY: number, originX: number, originY: number, baseScale: number,
    baseX: number, baseY: number, nextScale: number): void {
    const scale = this.clamp(nextScale, 1, ReaderComicView.MAX_ZOOM);
    const ratio = scale / Math.max(0.001, baseScale);
    const x = focusX - this.centerX() - ratio * (originX - this.centerX() - baseX);
    const y = focusY - this.centerY() - ratio * (originY - this.centerY() - baseY);
    this.applyZoom(scale, x, y);
  }

  private resetZoom(animated: boolean): void {
    if (!this.zoomed() && this.zoomX === 0 && this.zoomY === 0) return;
    if (animated) {
      animateTo({ duration: 220, curve: Curve.Friction }, () => this.applyZoom(1, 0, 0));
    } else {
      this.applyZoom(1, 0, 0);
    }
  }

  private tapPoint(event: GestureEvent): number[] {
    const finger = event.fingerList && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    return finger ? [finger.localX, finger.localY] : [this.centerX(), this.centerY()];
  }

  /** 点击手势默认不限制移动距离，拖动松手时也会识别成点击；拖过的触摸一律不算点击。 */
  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down && event.touches.length <= 1) this.touchDragged = false;
  }

  private handleDoubleTap(event: GestureEvent): void {
    if (this.touchDragged) return;
    if (this.zoomed()) {
      this.resetZoom(true);
      return;
    }
    const point = this.tapPoint(event);
    animateTo({ duration: 220, curve: Curve.Friction }, () => {
      this.zoomAround(point[0], point[1], point[0], point[1], 1, 0, 0, ReaderComicView.DOUBLE_TAP_ZOOM);
    });
  }

  private handleLongPress(event: GestureEvent): void {
    if (this.pinching) return;
    this.touchDragged = true;
    const point = this.tapPoint(event);
    const listX = this.centerX() + (point[0] - this.centerX() - this.zoomX) / this.zoomScale;
    const listY = this.centerY() + (point[1] - this.centerY() - this.zoomY) / this.zoomScale;
    try {
      const index = this.scroller.getItemIndex(listX, listY);
      const item = this.dataSource.itemAt(index);
      if (!item || !item.isPage() || !this.isImagePage(item.text)) return;
      const key = item.key;
      this.onImageLongPress(ReaderImageMarker.parse(item.text.trim()).source,
        (): void => this.retryRegistry.reload(key), ReaderComicImageItem.snapshotId(key));
    } catch (_) {
    }
  }

  private handleSingleTap(event: GestureEvent): void {
    if (this.touchDragged) return;
    const point = this.tapPoint(event);
    const width = Math.max(1, this.viewWidth);
    const height = Math.max(1, this.viewHeight);
    // 交互层盖住了失败提示：只有点中提示文字所在的居中一小块才重试，其余位置照常翻屏或呼出菜单，
    // 否则整章图片都失败时屏幕再也点不出菜单。命中测试换算回缩放前的列表坐标。
    const listX = this.centerX() + (point[0] - this.centerX() - this.zoomX) / this.zoomScale;
    const listY = this.centerY() + (point[1] - this.centerY() - this.zoomY) / this.zoomScale;
    try {
      const index = this.scroller.getItemIndex(listX, listY);
      if (index >= 0) {
        const rect = this.scroller.getItemRect(index);
        const nearHint = Math.abs(listY - (rect.y + rect.height / 2)) <= 44 &&
          Math.abs(listX - (rect.x + rect.width / 2)) <= rect.width * 0.35;
        if (nearHint && this.retryRegistry.retry(this.dataSource.getData(index).key)) return;
      }
    } catch (_) {
    }
    this.onTap(point[0], point[1], width, height);
  }

  private handlePinchStart(event: GestureEvent): void {
    this.pinching = true;
    this.touchDragged = true;
    // 先落下的手指可能已经触发了阅读页的拖动；交给缩放之后不能再滚列表或拉动切章。
    if (this.panInProgress && !this.zoomPanActive) {
      this.onPanCancel();
      this.zoomPanActive = true;
    }
    this.panResync = true;
    this.pinchBaseScale = this.zoomScale;
    this.pinchBaseX = this.zoomX;
    this.pinchBaseY = this.zoomY;
    this.pinchFocusX = event.pinchCenterX;
    this.pinchFocusY = event.pinchCenterY;
  }

  private handlePinchUpdate(event: GestureEvent): void {
    if (!this.pinching) return;
    this.zoomAround(event.pinchCenterX, event.pinchCenterY, this.pinchFocusX, this.pinchFocusY,
      this.pinchBaseScale, this.pinchBaseX, this.pinchBaseY, this.pinchBaseScale * event.scale);
  }

  private handlePinchEnd(): void {
    if (!this.pinching) return;
    this.pinching = false;
    this.panResync = true;
    if (this.zoomScale < 1.05) this.resetZoom(true);
  }

  private handlePanStart(): void {
    this.panInProgress = true;
    this.touchDragged = true;
    this.panLastX = 0;
    this.panLastY = 0;
    this.panResync = false;
    this.zoomPanActive = this.zoomed() || this.pinching;
    if (!this.zoomPanActive) this.onPanStart();
  }

  private handlePanUpdate(event: GestureEvent): void {
    if (!this.zoomPanActive) {
      this.onPanUpdate(event);
      return;
    }
    // 双指期间平移由捏合中心负责；松开一指后从当前位置重新计增量，避免画面跳动。
    if (this.pinching || this.panResync) {
      this.panLastX = event.offsetX;
      this.panLastY = event.offsetY;
      this.panResync = this.pinching;
      return;
    }
    const dx = event.offsetX - this.panLastX;
    const dy = event.offsetY - this.panLastY;
    this.panLastX = event.offsetX;
    this.panLastY = event.offsetY;
    this.panZoomed(dx, dy);
  }

  private handlePanEnd(event: GestureEvent): void {
    const zoomPan = this.zoomPanActive;
    this.panInProgress = false;
    this.zoomPanActive = false;
    if (!zoomPan) {
      this.onPanEnd(event);
      return;
    }
    if (!this.pinching && this.zoomed() && Math.abs(event.velocityY) > 120) {
      this.scroller.fling(event.velocityY / this.zoomScale);
    }
  }

  private handlePanCancel(): void {
    const zoomPan = this.zoomPanActive;
    this.panInProgress = false;
    this.zoomPanActive = false;
    if (!zoomPan) this.onPanCancel();
  }

  /**
   * 放大后的拖动：横向只移动画面；纵向优先滚动列表，列表到顶/到底后才移动画面，
   * 反向拖动时先把画面移回居中再滚列表，这样章首和章末被放大裁掉的部分也能看到。
   */
  private panZoomed(dx: number, dy: number): void {
    const boundX = (this.zoomScale - 1) * this.centerX();
    const boundY = (this.zoomScale - 1) * this.centerY();
    this.zoomX = this.clamp(this.zoomX + dx, -boundX, boundX);
    let remaining = dy;
    if (remaining > 0 && this.zoomY < 0) {
      const used = Math.min(remaining, -this.zoomY);
      this.zoomY += used;
      remaining -= used;
    } else if (remaining < 0 && this.zoomY > 0) {
      const used = Math.max(remaining, -this.zoomY);
      this.zoomY += used;
      remaining -= used;
    }
    if (Math.abs(remaining) < 0.01) return;
    let atTop = false;
    let atEnd = false;
    try {
      atTop = (Number(this.scroller.currentOffset().yOffset) || 0) <= 0.5;
      atEnd = this.scroller.isAtEnd();
    } catch (_) {
    }
    if ((remaining > 0 && atTop) || (remaining < 0 && atEnd)) {
      this.zoomY = this.clamp(this.zoomY + remaining, -boundY, boundY);
      return;
    }
    this.scroller.scrollBy(0, -remaining / this.zoomScale);
  }

  @Builder
  interactionLayer(doubleTap: boolean) {
    if (doubleTap) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .gesture(
          GestureGroup(GestureMode.Parallel,
            GestureGroup(GestureMode.Exclusive,
              TapGesture({ count: 2, distanceThreshold: this.panDistance })
                .onAction((event: GestureEvent) => this.handleDoubleTap(event)),
              TapGesture({ count: 1, distanceThreshold: this.panDistance })
                .onAction((event: GestureEvent) => this.handleSingleTap(event))
            ),
            LongPressGesture({ duration: 500 })
              .onAction((event: GestureEvent) => this.handleLongPress(event)),
            PinchGesture({ fingers: 2 })
              .onActionStart((event: GestureEvent) => this.handlePinchStart(event))
              .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
              .onActionEnd(() => this.handlePinchEnd())
              .onActionCancel(() => this.handlePinchEnd()),
            PanGesture({ direction: PanDirection.All, distance: this.panDistance })
              .onActionStart(() => this.handlePanStart())
              .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
              .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
              .onActionCancel(() => this.handlePanCancel())
          )
        )
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
        .gesture(
          GestureGroup(GestureMode.Parallel,
            TapGesture({ count: 1, distanceThreshold: this.panDistance })
              .onAction((event: GestureEvent) => this.handleSingleTap(event)),
            LongPressGesture({ duration: 500 })
              .onAction((event: GestureEvent) => this.handleLongPress(event)),
            PinchGesture({ fingers: 2 })
              .onActionStart((event: GestureEvent) => this.handlePinchStart(event))
              .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
              .onActionEnd(() => this.handlePinchEnd())
              .onActionCancel(() => this.handlePinchEnd()),
            PanGesture({ direction: PanDirection.All, distance: this.panDistance })
              .onActionStart(() => this.handlePanStart())
              .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
              .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
              .onActionCancel(() => this.handlePanCancel())
          )
        )
    }
  }

  /** 两话之间的分隔卡；下一话还没装进列表时显示加载状态。 */
  @Builder
  chapterSeparator(item: ReaderScrollItem) {
    Column({ space: AppSpacing.MD }) {
      Text('本话完')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.hintColor)
      Text(this.chapterTitle(item.chapterIndex))
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      if (item.pending) {
        Row({ space: AppSpacing.MD }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.hintColor)
          Text('正在加载下一话')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.hintColor)
        }
      } else if (item.failed) {
        Text('下一话加载失败，继续上拉重试')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.hintColor)
      }
    }
    .width('100%')
    .height(item.pending || item.failed ? 200 : 150)
    .padding({ left: 40, right: 40 })
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack() {
      List({ space: this.pageGap, scroller: this.scroller }) {
        LazyForEach(this.dataSource, (item: ReaderScrollItem, index: number) => {
          ListItem() {
            if (!item.isPage()) {
              this.chapterSeparator(item)
            } else if (this.isImagePage(item.text)) {
              ReaderComicImageItem({
                marker: item.text.trim(),
                viewWidth: this.viewWidth,
                viewHeight: this.viewHeight,
                fitScreen: this.fitScreen,
                seamOverlap: this.seamOverlap(index),
                pageLabel: `${item.pageIndex + 1}`,
                hintColor: this.hintColor,
                retryKey: item.key,
                superResolution: this.superResolution,
                textConvert: this.textConvert,
                retryRegistry: this.retryRegistry,
                onDenied: (): void => this.onImageDenied(item.chapterIndex)
              })
            } else {
              Text(LocalBookService.stripEpubImageMarkers(item.text).trim())
                .fontSize(AppFontSize.BODY_LARGE)
                .lineHeight(AppFontSize.BODY_LARGE * 1.7)
                .fontColor(this.textColor)
                .width('100%')
                .padding({ left: AppSpacing.XXXL, right: AppSpacing.XXXL, top: 56, bottom: 56 })
                .constraintSize({ minHeight: Math.max(200, this.viewHeight * 0.5) })
            }
          }
          .width('100%')
        }, (item: ReaderScrollItem) => item.key)
      }
      .width('100%')
      .height('100%')
      // 上一话装到列表前面、远处的章节从前面移除时，正在看的内容保持不动。
      .maintainVisibleContentPosition(true)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
      // 预先构建视口外的若干项，网络图片提前开始下载，快速下滑时少见空白占位。
      .cachedCount(Math.max(2, this.preloadCount))
      .scale({ x: this.zoomScale, y: this.zoomScale })
      .translate({ x: this.zoomX, y: this.zoomY + this.transitionY })
      .opacity(this.transitionOpacity)
      .onScrollIndex((start: number, end: number) => this.onVisibleRangeChange(start, end))
      .onReachEnd(() => this.onReachEnd())
      .onAppear(() => this.onListAppear())

      if (this.infoVisible) {
        ReaderComicInfoBadge({
          chapterText: this.infoChapter,
          pageText: this.infoPage,
          timeText: this.infoTime,
          battery: this.infoBattery
        })
          .position({ right: 10, bottom: this.infoBottomInset })
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.interactive) {
        this.interactionLayer(this.doubleTapZoom)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfaceColor)
    .clip(true)
  }
}
