import { common } from '@kit.AbilityKit';
import { util, worker, MessageEvents } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { ComicColorPixels } from './ComicColorPixels';
import { ComicColorJob, ComicColorMessage, ComicColorResult } from './ComicColorTypes';
import { ReaderComicImageExport } from './ReaderComicImageExport';
import { ReaderCacheBudget } from '../book/ReaderCacheBudget';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { ReaderComicComputeQueue } from './ReaderComicComputeQueue';

/** Single-page offline preview. The model and all image math live in a short-lived Worker. */
export class ComicColorizer {
  static readonly CANCELLED: string = '已取消着色';
  static readonly MEMBER_REQUIRED: string = '漫画着色为会员专享，开通会员后即可使用';
  private static readonly MAX_BYTES: number = 30 * 1024 * 1024;
  private static readonly MODEL_BYTES: number = 61596264;
  private static readonly MODEL_HASH: string = 'c212815a335a006b4bbf336af1c25c6158aaeac077f35f2775af381b83fe9934';
  private static queue: Promise<void> = Promise.resolve();

  static supported(): boolean {
    return canIUse('SystemCapability.AI.MindSporeLite');
  }

  /** Same membership tiers and bounded offline entitlement as comic super resolution. */
  static memberAllowed(): boolean {
    return AccountSessionStore.activeMembershipSku() !== '';
  }

  static colorize(context: common.Context, source: string, active: () => boolean,
    progress: (status: string) => void): Promise<ComicColorResult> {
    const job = ComicColorizer.queue.then(async (): Promise<ComicColorResult> => {
      ComicColorizer.check(active);
      if (!ComicColorizer.supported()) throw new Error('当前设备不支持本地着色引擎');
      return await ReaderComicComputeQueue.run(async (): Promise<ComicColorResult> => {
        ComicColorizer.check(active);
        return await ComicColorizer.run(context, source, active, progress);
      });
    });
    ComicColorizer.queue = job.then((): void => {}, (): void => {});
    return job;
  }

  private static check(active: () => boolean): void {
    if (!active()) throw new Error(ComicColorizer.CANCELLED);
    if (!ComicColorizer.memberAllowed()) throw new Error(ComicColorizer.MEMBER_REQUIRED);
  }

  private static async hash(bytes: Uint8Array): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: bytes });
    const result = await digest.digest();
    let hex = '';
    for (let i = 0; i < result.data.length; i++) hex += result.data[i].toString(16).padStart(2, '0');
    return hex;
  }

  private static async bytes(source: string): Promise<Uint8Array> {
    if (/^https?:/i.test(source)) return await ReaderComicImageExport.downloadImage(source);
    if (/^data:/i.test(source)) {
      const comma = source.indexOf(',');
      if (comma < 0 || !/;base64$/i.test(source.substring(0, comma)) ||
        source.length > ComicColorizer.MAX_BYTES * 1.4) throw new Error('图片数据无效或过大');
      return new util.Base64Helper().decodeSync(source.substring(comma + 1));
    }
    const path = /^file:/i.test(source) ? new fileUri.FileUri(source).path : source;
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(file.fd);
      if (stat.size <= 0 || stat.size > ComicColorizer.MAX_BYTES) throw new Error('图片为空或超过 30 MB');
      const buffer = new ArrayBuffer(stat.size);
      let read = 0;
      while (read < stat.size) {
        const part = new ArrayBuffer(stat.size - read);
        const count = await fs.read(file.fd, part, { length: part.byteLength });
        if (count <= 0) throw new Error('图片读取不完整');
        new Uint8Array(buffer).set(new Uint8Array(part, 0, count), read);
        read += count;
      }
      return new Uint8Array(buffer);
    } finally {
      await fs.close(file);
    }
  }

  private static async modelPath(context: common.Context): Promise<string> {
    const dir = `${context.filesDir}/comic_colorizer`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    const path = `${dir}/${ComicColorPixels.VERSION}.ms`;
    if (fs.accessSync(path) && (await fs.stat(path)).size === ComicColorizer.MODEL_BYTES) return path;
    const bytes = await context.resourceManager.getRawFileContent('comic-colorizer/alac.ms');
    if (bytes.length !== ComicColorizer.MODEL_BYTES || await ComicColorizer.hash(bytes) !== ComicColorizer.MODEL_HASH) {
      throw new Error('本地着色模型损坏，请重新安装应用');
    }
    await ComicColorizer.write(path, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    return path;
  }

  private static async write(path: string, bytes: ArrayBuffer): Promise<void> {
    const temp = `${path}.part`;
    const file = await fs.open(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.byteLength) {
        const count = await fs.write(file.fd, bytes.slice(offset));
        if (count <= 0) throw new Error('无法写入着色结果');
        offset += count;
      }
    } catch (error) {
      try { fs.unlinkSync(temp); } catch (_) {}
      throw error as Error;
    } finally {
      await fs.close(file);
    }
    try {
      await fs.rename(temp, path);
    } catch (error) {
      try { fs.unlinkSync(temp); } catch (_) {}
      throw error as Error;
    }
  }

  private static async run(context: common.Context, source: string, active: () => boolean,
    progress: (status: string) => void): Promise<ComicColorResult> {
    const started = Date.now();
    progress('正在读取原图…');
    const bytes = await ComicColorizer.bytes(source);
    ComicColorizer.check(active);
    if (!bytes.length || bytes.length > ComicColorizer.MAX_BYTES) throw new Error('图片为空或超过 30 MB');
    const key = await ComicColorizer.hash(bytes);
    const dir = `${context.cacheDir}/comic_images`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    const path = `${dir}/color_${ComicColorPixels.VERSION}_${key}.jpg`;
    const result = new ComicColorResult();
    ComicColorizer.check(active);
    if (fs.accessSync(path) && (await fs.stat(path)).size > 0) {
      ComicColorizer.check(active);
      ReaderCacheBudget.touchComicFile(path);
      result.uri = fileUri.getUriFromPath(path);
      result.cached = true;
      return result;
    }
    progress('正在准备本地模型…');
    const modelPath = await ComicColorizer.modelPath(context);
    ComicColorizer.check(active);
    const job = new ComicColorJob();
    job.modelPath = modelPath;
    job.imageBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const message = await ComicColorizer.execute(job, active, progress);
    ComicColorizer.check(active);
    await ComicColorizer.write(path, message.jpeg);
    ReaderCacheBudget.noteComicWrite();
    ComicColorizer.check(active);
    result.uri = fileUri.getUriFromPath(path);
    result.elapsedMs = Date.now() - started;
    result.inferenceMs = message.inferenceMs;
    console.info(`[ComicColor] ${message.width}x${message.height} total=${result.elapsedMs}ms infer=${result.inferenceMs}ms`);
    return result;
  }

  private static execute(job: ComicColorJob, active: () => boolean,
    progress: (status: string) => void): Promise<ComicColorMessage> {
    return new Promise<ComicColorMessage>((resolve, reject): void => {
      const thread = new worker.ThreadWorker('../../workers/ComicColorWorker.ets', { name: 'ComicColor' });
      let settled = false;
      let cancelReason = '';
      const started = Date.now();
      // Never terminate during predict(): the native async callback can outlive the JS VM and crash the process.
      // Keep the serial queue occupied until the worker acknowledges safe completion; UI cancellation is immediate.
      const requestCancel = (reason: string): void => {
        if (cancelReason) return;
        cancelReason = reason;
        const cancellation = new ComicColorJob();
        cancellation.cancel = true;
        try { thread.postMessage(cancellation); } catch (_) {}
      };
      const finish = (message: ComicColorMessage | null, error: string): void => {
        if (settled) return;
        settled = true;
        clearInterval(timer);
        try { thread.terminate(); } catch (_) {}
        if (message) resolve(message);
        else reject(new Error(error));
      };
      const timer = setInterval((): void => {
        if (!active()) requestCancel(ComicColorizer.CANCELLED);
        else if (!ComicColorizer.memberAllowed()) requestCancel(ComicColorizer.MEMBER_REQUIRED);
        else if (Date.now() - started > 180000 && !cancelReason) {
          requestCancel('本机着色超时，请稍后重试');
          progress('着色超时，正在等待本地引擎安全结束，可返回阅读');
        }
      }, 100);
      thread.onmessage = (event: MessageEvents): void => {
        if (settled) return;
        if (!active()) requestCancel(ComicColorizer.CANCELLED);
        else if (!ComicColorizer.memberAllowed()) requestCancel(ComicColorizer.MEMBER_REQUIRED);
        const message = event.data as ComicColorMessage;
        if (message.error) finish(null, cancelReason || message.error);
        else if (message.jpeg && message.jpeg.byteLength > 0) {
          if (cancelReason) finish(null, cancelReason);
          else finish(message, '');
        } else if (message.status && !cancelReason) progress(message.status);
      };
      thread.onerror = (): void => finish(null, '本地着色线程运行失败，请重试');
      thread.onmessageerror = (): void => finish(null, '无法读取本地着色结果');
      thread.onexit = (): void => finish(null, '本地着色线程已退出，请重试');
      try { thread.postMessage(job, [job.imageBytes]); }
      catch (_) { finish(null, '本地着色任务启动失败'); }
    });
  }
}
