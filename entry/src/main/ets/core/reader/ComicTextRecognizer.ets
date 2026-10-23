import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import image from '@ohos.multimedia.image';
import deviceInfo from '@ohos.deviceInfo';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import lazy { textRecognition } from '@kit.CoreVisionKit';
import { digestHashHex } from '@legado/sourceengine';
import { ReaderComicImageExport } from './ReaderComicImageExport';
import { ReaderCacheBudget } from '../book/ReaderCacheBudget';
import {
  ComicTextColors, ComicTextColorSampler, ComicTextGeometry, ComicTextPoint, ComicTextRegion, ComicTextResult
} from './ComicTextTypes';

/**
 * 漫画图片的端侧 OCR：无内容上传，全局串行，离开页面或划走后停止后续分块并丢弃结果。
 * 识别时顺带从输入切片取每行字的底色和字色，供图上重写判断能否安全覆盖。
 * 系统服务在连续使用期间保持初始化，空闲一会儿后释放。
 */
export class ComicTextRecognizer {
  static readonly CANCELLED: string = '漫画文字识别已取消';
  private static readonly MAX_BYTES: number = 30 * 1024 * 1024;
  private static readonly CACHE_VERSION: number = 4;
  private static readonly ENGINE_IDLE_MS: number = 30 * 1000;
  private static queue: Promise<void> = Promise.resolve();
  private static engineReady: boolean = false;
  private static engineIdleTimer: number = -1;
  private static languages: string[] = [];

  static supported(): boolean {
    try {
      return canIUse('SystemCapability.AI.OCR.TextRecognition');
    } catch (_) {
      return false;
    }
  }

  static recognize(context: common.Context, source: string, active: () => boolean,
    progress: (done: number, total: number) => void, force: boolean = false): Promise<ComicTextResult> {
    const job = ComicTextRecognizer.queue.then(async (): Promise<ComicTextResult> => {
      try {
        ComicTextRecognizer.check(active);
        if (!ComicTextRecognizer.supported()) throw new Error('当前设备不支持系统文字识别');
        return await ComicTextRecognizer.run(context, source, active, progress, force);
      } finally {
        ComicTextRecognizer.scheduleRelease();
      }
    });
    ComicTextRecognizer.queue = job.then((): void => {}, (): void => {});
    return job;
  }

  private static check(active: () => boolean): void {
    if (!active()) throw new Error(ComicTextRecognizer.CANCELLED);
  }

  /** 缓存键：本地文件按路径、大小、修改时间；网络图按地址；内嵌数据按内容。 */
  private static async identity(source: string): Promise<string> {
    if (/^https?:/i.test(source)) return source;
    if (/^data:/i.test(source)) return `data\n${digestHashHex('SHA256', source)}`;
    const path = ComicTextRecognizer.localPath(source);
    const stat = await fs.stat(path);
    if (!stat.isFile() || stat.size <= 0 || stat.size > ComicTextRecognizer.MAX_BYTES) {
      throw new Error('图片文件为空或超过 30 MB');
    }
    return `${path}\n${stat.size}\n${stat.mtime}`;
  }

  private static localPath(source: string): string {
    return /^file:/i.test(source) ? new fileUri.FileUri(source).path : source;
  }

  private static async bytes(source: string): Promise<Uint8Array> {
    if (/^https?:/i.test(source)) return await ReaderComicImageExport.downloadImage(source);
    const comma = source.indexOf(',');
    if (comma < 0 || !/;base64$/i.test(source.substring(0, comma)) ||
      source.length > ComicTextRecognizer.MAX_BYTES * 1.4) {
      throw new Error('图片数据无效或过大');
    }
    return new util.Base64Helper().decodeSync(source.substring(comma + 1));
  }

  private static async run(context: common.Context, source: string, active: () => boolean,
    progress: (done: number, total: number) => void, force: boolean): Promise<ComicTextResult> {
    const started = Date.now();
    const key = digestHashHex('SHA256',
      `${ComicTextRecognizer.CACHE_VERSION}\n${await ComicTextRecognizer.identity(source)}`);
    const dir = `${context.cacheDir}/comic_images`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    const cache = `${dir}/ocr_v${ComicTextRecognizer.CACHE_VERSION}_${key}.json`;
    ComicTextRecognizer.check(active);
    if (!force) {
      const cached = ComicTextRecognizer.readCache(cache, key);
      if (cached) return cached;
    }
    const result = new ComicTextResult();
    result.imageHash = key;
    result.engineVersion = deviceInfo.osFullName;
    let file: fs.File | null = null;
    let imageSource: image.ImageSource;
    if (/^(?:https?|data):/i.test(source)) {
      const bytes = await ComicTextRecognizer.bytes(source);
      if (!bytes.length || bytes.length > ComicTextRecognizer.MAX_BYTES) throw new Error('图片为空或过大');
      imageSource = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    } else {
      file = fs.openSync(ComicTextRecognizer.localPath(source), fs.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(file.fd);
    }
    try {
      ComicTextRecognizer.check(active);
      const info = await imageSource.getImageInfo();
      result.width = info.size.width;
      result.height = info.size.height;
      const tiles = ComicTextGeometry.tiles(result.width, result.height);
      result.tileCount = tiles.length;
      await ComicTextRecognizer.ensureEngine();
      result.supportedLanguages = ComicTextRecognizer.languages;
      for (let index = 0; index < tiles.length; index++) {
        ComicTextRecognizer.check(active);
        progress(index, tiles.length);
        const tile = tiles[index];
        const pixelMap = await imageSource.createPixelMap({
          desiredRegion: { x: 0, y: tile.y, size: { width: result.width, height: tile.height } },
          desiredSize: { width: tile.outputWidth, height: tile.outputHeight },
          cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        });
        try {
          ComicTextRecognizer.check(active);
          const decoded = await pixelMap.getImageInfo();
          const recognized = await textRecognition.recognizeText({ pixelMap: pixelMap },
            { isDirectionDetectionSupported: true });
          ComicTextRecognizer.check(active);
          let pixels: Uint8Array | null = null;
          try {
            const buffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
            await pixelMap.readPixelsToBuffer(buffer);
            pixels = new Uint8Array(buffer);
          } catch (_) {
            // 读不到像素只是不能判断底色，这页按“不覆盖”处理，识别结果照常使用。
          }
          const stride = pixelMap.getBytesNumberPerRow();
          const bgra = decoded.pixelFormat === image.PixelMapFormat.BGRA_8888;
          // 先收齐本块所有行框（切片坐标），判断底色时要跳过相邻行的字。
          const tileLines: ComicTextPoint[][] = [];
          const tileRegions: (ComicTextRegion | null)[] = [];
          let lineIndex = 0;
          for (let blockIndex = 0; blockIndex < recognized.blocks.length; blockIndex++) {
            for (const line of recognized.blocks[blockIndex].lines) {
              const points: ComicTextPoint[] = line.cornerPoints.map((point: textRecognition.PixelPoint): ComicTextPoint => {
                const mapped = new ComicTextPoint();
                mapped.x = point.x;
                mapped.y = point.y;
                return mapped;
              });
              const region: ComicTextRegion | null = ComicTextGeometry.mapLine(`${index}_${lineIndex++}`, line.value,
                points, tile, result.width, decoded.size.width, decoded.size.height);
              if (region) region.group = `${index}_b${blockIndex}`;
              tileLines.push(points);
              tileRegions.push(region);
            }
          }
          if (pixels) {
            const backgrounds: string[] = [];
            for (let lineAt = 0; lineAt < tileRegions.length; lineAt++) {
              const region = tileRegions[lineAt];
              const colors: ComicTextColors = region ? ComicTextColorSampler.sample(pixels, decoded.size.width,
                decoded.size.height, stride, bgra, tileLines[lineAt], tileLines) : new ComicTextColors();
              backgrounds.push(colors.background);
              if (region) {
                region.background = colors.background;
                region.foreground = colors.foreground;
              }
            }
            // 第二遍：贴着气泡边线的行借相邻行的底色重判（只用第一遍的结果，不连锁借用）。
            for (let lineAt = 0; lineAt < tileRegions.length; lineAt++) {
              const region = tileRegions[lineAt];
              if (!region || region.background) continue;
              const fallback = ComicTextColorSampler.neighborBackground(lineAt, tileLines, backgrounds);
              if (!fallback) continue;
              const colors: ComicTextColors = ComicTextColorSampler.sample(pixels, decoded.size.width,
                decoded.size.height, stride, bgra, tileLines[lineAt], tileLines, fallback);
              region.background = colors.background;
              region.foreground = colors.foreground;
            }
          }
          for (const region of tileRegions) {
            if (region) result.regions.push(region);
          }
          if (result.regions.length > 5000) throw new Error('图片文字过多，请分段后识别');
        } finally {
          await pixelMap.release();
        }
      }
      ComicTextRecognizer.check(active);
      result.elapsedMs = Date.now() - started;
      ComicTextRecognizer.writeCache(cache, result);
      progress(tiles.length, tiles.length);
      return result;
    } catch (error) {
      // 服务异常后下次重新初始化；取消不算服务异常。
      if ((error as Error)?.message !== ComicTextRecognizer.CANCELLED) await ComicTextRecognizer.releaseEngine();
      throw error as Error;
    } finally {
      try {
        await imageSource.release();
      } catch (_) {
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private static async ensureEngine(): Promise<void> {
    if (ComicTextRecognizer.engineReady) return;
    if (!await textRecognition.init()) throw new Error('系统文字识别服务暂不可用，请重试');
    ComicTextRecognizer.engineReady = true;
    try {
      ComicTextRecognizer.languages = await textRecognition.getSupportedLanguages();
    } catch (_) {
      ComicTextRecognizer.languages = [];
    }
  }

  private static scheduleRelease(): void {
    if (ComicTextRecognizer.engineIdleTimer >= 0) clearTimeout(ComicTextRecognizer.engineIdleTimer);
    ComicTextRecognizer.engineIdleTimer = -1;
    if (!ComicTextRecognizer.engineReady) return;
    ComicTextRecognizer.engineIdleTimer = setTimeout(() => {
      ComicTextRecognizer.engineIdleTimer = -1;
      // 排进队列，等正在跑的识别结束再释放；之后的任务会重新初始化。
      ComicTextRecognizer.queue = ComicTextRecognizer.queue
        .then((): Promise<void> => ComicTextRecognizer.releaseEngine());
    }, ComicTextRecognizer.ENGINE_IDLE_MS);
  }

  private static async releaseEngine(): Promise<void> {
    if (!ComicTextRecognizer.engineReady) return;
    ComicTextRecognizer.engineReady = false;
    try {
      await textRecognition.release();
    } catch (_) {
    }
  }

  private static readCache(path: string, key: string): ComicTextResult | null {
    try {
      if (!fs.accessSync(path)) return null;
      const stat = fs.statSync(path);
      if (stat.size > 2 * 1024 * 1024) return null;
      const parsed = JSON.parse(fs.readTextSync(path)) as ComicTextResult;
      if (parsed.version !== ComicTextRecognizer.CACHE_VERSION || parsed.imageHash !== key ||
        parsed.engineVersion !== deviceInfo.osFullName || !Array.isArray(parsed.regions) ||
        parsed.regions.length > 5000 || !Array.isArray(parsed.supportedLanguages)) {
        return null;
      }
      ComicTextGeometry.tiles(parsed.width, parsed.height);
      for (const region of parsed.regions) {
        if (!region || typeof region.text !== 'string' || typeof region.id !== 'string' ||
          typeof region.group !== 'string' || typeof region.background !== 'string' ||
          typeof region.foreground !== 'string' || !Array.isArray(region.points) || region.points.length !== 4) {
          return null;
        }
        for (const point of region.points) {
          if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return null;
        }
      }
      ReaderCacheBudget.touchComicFile(path);
      return parsed;
    } catch (_) {
      return null;
    }
  }

  private static writeCache(path: string, result: ComicTextResult): void {
    const temporary = `${path}.tmp`;
    try {
      const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(result));
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(temporary, path);
      ReaderCacheBudget.noteComicWrite();
    } catch (_) {
      // 缓存不可写不影响当前页；不给日志写入漫画原文或图片地址。
      try {
        if (fs.accessSync(temporary)) fs.unlinkSync(temporary);
      } catch (_) {
      }
    }
  }
}
