import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import image from '@ohos.multimedia.image';
import deviceInfo from '@ohos.deviceInfo';
import lazy { imageSuperResolution, visionBase } from '@kit.CoreVisionKit';
import { digestHashHex } from '@legado/sourceengine';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { ReaderCacheBudget } from '../book/ReaderCacheBudget';
import { ReaderComicImageExport } from './ReaderComicImageExport';
import { ReaderComicComputeQueue } from './ReaderComicComputeQueue';

/** 漫画超分当前能否使用。 */
export class ReaderComicSuperResolutionAccess {
  static readonly READY: string = 'ready';
  /** 系统低于 API 26 或设备没有视觉能力。 */
  static readonly UNSUPPORTED: string = 'unsupported';
  /** 未登录、未开通或会员已到期。 */
  static readonly MEMBER_REQUIRED: string = 'member';
}

/**
 * 漫画图片的端侧超分（系统 CoreVisionKit 图片超分，API 26 起，固定 4 倍放大，单次输入不超过 2048×2048）。
 *
 * - 输出宽度取显示宽度的 2 倍（双击放大后仍清楚），原图已经这么宽或更宽（超过 2048）时不处理；
 *   超分后缩到输出宽度存成 JPEG，不改原图。超长图按像素上限降低输出宽度，而不是放弃。
 * - 长条漫按横条分块超分再拼接，块之间留重叠行，拼接处取各块中间部分，避免接缝。
 * - 全局串行；正在看的图片才排队，排到时已划走就跳过。引擎空闲一会儿后释放。
 * - 结果和漫画图片缓存放在同一目录（文件名带 sr_ 前缀），一起受 1 GiB 上限约束、一起清理。
 */
export class ReaderComicSuperResolution {
  private static readonly SR_SCALE: number = 4;
  private static readonly MAX_INPUT_SIDE: number = 2048;
  /** 单块输入像素上限：4 倍后的输出约 8M 像素（32 MB），控制峰值内存。 */
  private static readonly MAX_TILE_PIXELS: number = 512 * 1024;
  private static readonly TILE_OVERLAP: number = 16;
  /** 拼接结果上限，约 48 MB 内存；超长图按此降低输出宽度。 */
  private static readonly MAX_OUTPUT_PIXELS: number = 12 * 1024 * 1024;
  private static readonly MAX_SOURCE_BYTES: number = 20 * 1024 * 1024;
  /** 输出宽度相对显示宽度的倍数。 */
  private static readonly DISPLAY_SCALE: number = 2;
  /** 输出宽度不到原图宽度这么多倍时，超分看不出差别，不处理。 */
  private static readonly MIN_GAIN: number = 1.15;
  /** 系统模型首次加载时第一次请求可能报服务异常，稍等后重试。 */
  private static readonly ENGINE_RETRY_DELAY_MS: number = 800;
  private static readonly ENGINE_IDLE_MS: number = 30 * 1000;
  private static readonly MAX_ENGINE_FAILURES: number = 3;
  private static readonly CACHE_VERSION: string = 'v2';

  private static queue: Promise<void> = Promise.resolve();
  private static engine: imageSuperResolution.ImageSRAnalyzer | null = null;
  private static engineIdleTimer: number = -1;
  private static engineFailures: number = 0;
  /** 系统超分服务连续出错后本次运行不再尝试。 */
  private static disabled: boolean = false;
  /** 已判定不必或无法处理的图片，避免反复解码。 */
  private static readonly skipped: Set<string> = new Set<string>();

  static supported(): boolean {
    if (ReaderComicSuperResolution.disabled) return false;
    try {
      return deviceInfo.sdkApiVersion >= 26 && canIUse('SystemCapability.AI.Vision.VisionBase');
    } catch (_) {
      return false;
    }
  }

  static memberAllowed(): boolean {
    return AccountSessionStore.activeMembershipSku() !== '';
  }

  static access(): string {
    if (!ReaderComicSuperResolution.supported()) return ReaderComicSuperResolutionAccess.UNSUPPORTED;
    if (!ReaderComicSuperResolution.memberAllowed()) return ReaderComicSuperResolutionAccess.MEMBER_REQUIRED;
    return ReaderComicSuperResolutionAccess.READY;
  }

  /**
   * 排队处理一张图，成功返回超分结果的 file:// 地址；不需要、不支持或失败时返回空串。
   * @param targetWidth 图片在屏幕上的显示宽度（物理像素）
   * @param active 图片仍在屏幕上且开关仍开着
   */
  static enhance(source: string, targetWidth: number, active: () => boolean): Promise<string> {
    const job = ReaderComicSuperResolution.queue.then(async (): Promise<string> => {
      if (!active() || ReaderComicSuperResolution.access() !== ReaderComicSuperResolutionAccess.READY) return '';
      try {
        return await ReaderComicComputeQueue.run(async (): Promise<string> => {
          if (!active() || ReaderComicSuperResolution.access() !== ReaderComicSuperResolutionAccess.READY) return '';
          return await ReaderComicSuperResolution.process(source, Math.round(targetWidth), active);
        });
      } catch (error) {
        console.warn(`[ComicSR] 超分失败，继续显示原图: ${(error as Error)?.message || error}`);
        return '';
      } finally {
        ReaderComicSuperResolution.scheduleEngineRelease();
      }
    });
    ReaderComicSuperResolution.queue = job.then((): void => {}, (): void => {});
    return job;
  }

  private static async process(source: string, targetWidth: number, active: () => boolean): Promise<string> {
    const cacheDir = AppStorage.get<string>('appCacheDir') || '';
    if (!cacheDir || !source || targetWidth < 64) return '';
    const network = /^https?:/i.test(source);
    let localPath = '';
    let identity = source;
    if (!network) {
      if (/^data:/i.test(source)) return '';
      localPath = /^file:/i.test(source) ? new fileUri.FileUri(source).path : source;
      const stat = await fs.stat(localPath);
      if (stat.size <= 0 || stat.size > ReaderComicSuperResolution.MAX_SOURCE_BYTES) return '';
      identity = `${localPath}\n${stat.size}\n${stat.mtime}`;
    }
    const key = digestHashHex('SHA256', `${ReaderComicSuperResolution.CACHE_VERSION}\n${identity}\n${targetWidth}`);
    if (ReaderComicSuperResolution.skipped.has(key)) return '';
    if (ReaderComicSuperResolution.skipped.size > 4096) ReaderComicSuperResolution.skipped.clear();
    const dir = `${cacheDir}/comic_images`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    const outputPath = `${dir}/sr_${key}.jpg`;
    if (fs.accessSync(outputPath)) {
      ReaderCacheBudget.touchComicFile(outputPath);
      return fileUri.getUriFromPath(outputPath);
    }

    let imageSource: image.ImageSource | null = null;
    let file: fs.File | null = null;
    try {
      if (network) {
        const bytes = await ReaderComicImageExport.downloadImage(source);
        if (!active()) return '';
        imageSource = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      } else {
        file = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
        imageSource = image.createImageSource(file.fd);
      }
      const info = await imageSource.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      const gain = Math.min(ReaderComicSuperResolution.SR_SCALE,
        targetWidth * ReaderComicSuperResolution.DISPLAY_SCALE / Math.max(1, width),
        Math.sqrt(ReaderComicSuperResolution.MAX_OUTPUT_PIXELS / Math.max(1, width * height)));
      const outWidth = Math.round(width * gain);
      const outHeight = Math.round(height * gain);
      if (width < 32 || height < 32 || width > ReaderComicSuperResolution.MAX_INPUT_SIDE ||
        gain < ReaderComicSuperResolution.MIN_GAIN || (await imageSource.getFrameCount()) !== 1) {
        console.info(`[ComicSR] 跳过 ${width}x${height} 显示宽度=${targetWidth} 倍数=${gain.toFixed(2)}`);
        ReaderComicSuperResolution.skipped.add(key);
        return '';
      }
      const startedAt = Date.now();
      const result = await ReaderComicSuperResolution.upscale(imageSource, width, height, outWidth, outHeight, active);
      if (!result) return '';
      try {
        // 已经算完的结果即使图片刚被划走也存下来，回看时直接用。
        await ReaderComicSuperResolution.writeJpeg(result, outputPath);
      } finally {
        await result.release();
      }
      ReaderCacheBudget.noteComicWrite();
      console.info(`[ComicSR] 完成 ${width}x${height} -> ${outWidth}x${outHeight} 用时 ${Date.now() - startedAt}ms`);
      return active() ? fileUri.getUriFromPath(outputPath) : '';
    } finally {
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

  /** 按横条分块超分，缩到输出宽度后写进结果图；途中划走则放弃并返回 null。 */
  private static async upscale(imageSource: image.ImageSource, width: number, height: number,
    outWidth: number, outHeight: number, active: () => boolean): Promise<image.PixelMap | null> {
    const ratio = outWidth / width;
    const overlap = ReaderComicSuperResolution.TILE_OVERLAP;
    const step = Math.max(64, Math.min(ReaderComicSuperResolution.MAX_INPUT_SIDE - overlap * 2,
      Math.floor(ReaderComicSuperResolution.MAX_TILE_PIXELS / width) - overlap * 2));
    const output = image.createPixelMapSync({
      size: { width: outWidth, height: outHeight },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
    let completed = false;
    try {
      for (let top = 0; top < height; top += step) {
        if (!active()) return null;
        const bottom = Math.min(height, top + step);
        // 每块多读上下重叠行，拼接时只取本块负责的 [top, bottom) 部分。
        const readTop = Math.max(0, top - overlap);
        const readBottom = Math.min(height, bottom + overlap);
        const tile = await imageSource.createPixelMap({
          desiredRegion: { x: 0, y: readTop, size: { width: width, height: readBottom - readTop } },
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        });
        try {
          const enhanced = await ReaderComicSuperResolution.runEngine(tile);
          try {
            if (!active()) return null;
            const destTop = Math.round(top * ratio);
            const destBottom = bottom >= height ? outHeight : Math.round(bottom * ratio);
            const scaledTop = Math.round(readTop * ratio);
            const scaledHeight = Math.round(readBottom * ratio) - scaledTop;
            const enhancedSize = (await enhanced.getImageInfo()).size;
            if (enhancedSize.width <= 0 || enhancedSize.height <= 0) throw new Error('超分结果为空');
            await enhanced.scale(outWidth / enhancedSize.width, scaledHeight / enhancedSize.height,
              image.AntiAliasingLevel.HIGH);
            const scaledSize = (await enhanced.getImageInfo()).size;
            const offsetY = destTop - scaledTop;
            const rows = Math.min(destBottom - destTop, scaledSize.height - offsetY);
            const columns = Math.min(outWidth, scaledSize.width);
            if (rows <= 0 || columns <= 0) throw new Error('超分结果尺寸异常');
            // readPixels/writePixels 都按 BGRA_8888 交换数据，结果图仍是 RGBA_8888。
            const pixels = new ArrayBuffer(columns * rows * 4);
            const region: image.Region = { x: 0, y: offsetY, size: { width: columns, height: rows } };
            await enhanced.readPixels({ pixels: pixels, offset: 0, stride: columns * 4, region: region });
            await output.writePixels({
              pixels: pixels,
              offset: 0,
              stride: columns * 4,
              region: { x: 0, y: destTop, size: { width: columns, height: rows } }
            });
          } finally {
            if (enhanced !== tile) await enhanced.release();
          }
        } finally {
          await tile.release();
        }
      }
      completed = true;
      return output;
    } finally {
      if (!completed) await output.release();
    }
  }

  private static async runEngine(input: image.PixelMap): Promise<image.PixelMap> {
    if (ReaderComicSuperResolution.engineIdleTimer >= 0) {
      clearTimeout(ReaderComicSuperResolution.engineIdleTimer);
      ReaderComicSuperResolution.engineIdleTimer = -1;
    }
    try {
      if (!ReaderComicSuperResolution.engine) {
        ReaderComicSuperResolution.engine = await imageSuperResolution.ImageSRAnalyzer.create();
      }
      const engine = ReaderComicSuperResolution.engine;
      const request: visionBase.Request = { inputData: { pixelMap: input } };
      let response: imageSuperResolution.ISPResponse;
      try {
        response = await engine.process(request);
      } catch (_) {
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, ReaderComicSuperResolution.ENGINE_RETRY_DELAY_MS);
        });
        response = await engine.process(request);
      }
      ReaderComicSuperResolution.engineFailures = 0;
      return response.pixelMap;
    } catch (error) {
      ReaderComicSuperResolution.engineFailures++;
      if (ReaderComicSuperResolution.engineFailures >= ReaderComicSuperResolution.MAX_ENGINE_FAILURES) {
        ReaderComicSuperResolution.disabled = true;
        console.warn('[ComicSR] 系统超分服务连续出错，本次运行停用');
      }
      await ReaderComicSuperResolution.releaseEngine();
      throw error as Error;
    }
  }

  private static scheduleEngineRelease(): void {
    if (!ReaderComicSuperResolution.engine || ReaderComicSuperResolution.engineIdleTimer >= 0) return;
    ReaderComicSuperResolution.engineIdleTimer = setTimeout(() => {
      ReaderComicSuperResolution.engineIdleTimer = -1;
      // 排队中的任务会在用到时重新创建。
      ReaderComicSuperResolution.queue = ReaderComicSuperResolution.queue
        .then((): Promise<void> => ReaderComicSuperResolution.releaseEngine());
    }, ReaderComicSuperResolution.ENGINE_IDLE_MS);
  }

  private static async releaseEngine(): Promise<void> {
    const engine = ReaderComicSuperResolution.engine;
    ReaderComicSuperResolution.engine = null;
    if (!engine) return;
    try {
      await engine.destroy();
    } catch (_) {
    }
  }

  private static async writeJpeg(pixelMap: image.PixelMap, path: string): Promise<void> {
    const packer = image.createImagePacker();
    const temporary = `${path}.tmp`;
    try {
      const data = await packer.packToData(pixelMap, { format: 'image/jpeg', quality: 92 });
      const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < data.byteLength) {
          const written = fs.writeSync(file.fd, data.slice(offset));
          if (written <= 0) throw new Error('超分结果写入不完整');
          offset += written;
        }
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(temporary, path);
    } finally {
      try {
        if (fs.accessSync(temporary)) fs.unlinkSync(temporary);
      } catch (_) {
      }
      await packer.release();
    }
  }
}
