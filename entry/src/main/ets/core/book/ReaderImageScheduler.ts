import { HttpClient } from '@legado/sourceengine';

class ReaderImageTicket {
  seq: number = 0;
  priority: () => number = (): number => ReaderImageScheduler.FOREGROUND;
  cancelled: () => boolean = (): boolean => false;
  start: (background: boolean) => void = (_background: boolean): void => {};
  reject: (error: Error) => void = (): void => {};
}

/**
 * 全应用共用的正文图片名额，默认 4，可在网络设置中选择 8 或 12。
 * 当前章、预加载的相邻章和缓存全文共用名额：当前章优先；当前章有图片时后台最多占 1 个，
 * 没有时最多占 2 个。
 * 优先级在每次分配名额时重新读取，预加载的章节变成当前章后，剩下的图片随即提前。
 * 小于 BACKGROUND 的都算前台，数值越小越先处理：屏幕上正等着的图片是 VISIBLE，
 * 已经挂载在屏幕附近（条漫的缓存项、翻页模式后面几页）的是 NEAR。
 */
export class ReaderImageScheduler {
  static readonly VISIBLE: number = -2;
  static readonly NEAR: number = -1;
  static readonly FOREGROUND: number = 0;
  static readonly BACKGROUND: number = 1;
  static readonly DEFAULT_CONCURRENCY: number = 4;
  private static maxActive: number = ReaderImageScheduler.DEFAULT_CONCURRENCY;
  static readonly MAX_BACKGROUND: number = 1;
  /** 当前章没有图片在下载或排队时，后台可以多用一个名额；当前章新来的图片先拿其余空着的名额。 */
  static readonly MAX_BACKGROUND_IDLE: number = 2;
  private static readonly PURGE_INTERVAL_MS: number = 200;

  private static sequence: number = 0;
  private static active: number = 0;
  private static activeBackground: number = 0;
  private static queue: ReaderImageTicket[] = [];
  private static purgeTimer: number = -1;

  static readonly foreground: () => number = (): number => ReaderImageScheduler.FOREGROUND;

  static normalizeConcurrency(value: number): number {
    return [4, 8, 12].includes(value) ? value : ReaderImageScheduler.DEFAULT_CONCURRENCY;
  }

  static get concurrency(): number { return ReaderImageScheduler.maxActive; }

  /** 调低上限只停止发新任务，已启动的下载/解密自然完成；调高后立即分配新空位。 */
  static setConcurrency(value: number): void {
    ReaderImageScheduler.maxActive = ReaderImageScheduler.normalizeConcurrency(value);
    ReaderImageScheduler.pump();
  }

  /** 排到名额后执行 task；排队期间被取消时以 HttpClient.CANCELLED_ERROR 结束，不再执行。 */
  static async run<T>(priority: () => number, cancelled: () => boolean, task: () => Promise<T>): Promise<T> {
    if (cancelled()) throw new Error(HttpClient.CANCELLED_ERROR);
    let background = false;
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      const ticket = new ReaderImageTicket();
      ticket.seq = ++ReaderImageScheduler.sequence;
      ticket.priority = priority;
      ticket.cancelled = cancelled;
      ticket.start = (startedInBackground: boolean): void => {
        background = startedInBackground;
        resolve();
      };
      ticket.reject = reject;
      ReaderImageScheduler.queue.push(ticket);
      ReaderImageScheduler.pump();
    });
    try {
      return await task();
    } finally {
      ReaderImageScheduler.active--;
      if (background) ReaderImageScheduler.activeBackground--;
      ReaderImageScheduler.pump();
    }
  }

  private static pump(): void {
    ReaderImageScheduler.purgeCancelled();
    while (ReaderImageScheduler.active < ReaderImageScheduler.maxActive) {
      // 队列按提交顺序排列，各取最早的一张，即本章靠前的图片先处理。
      let firstForeground = -1;
      let foregroundPriority = 0;
      let firstBackground = -1;
      for (let index = 0; index < ReaderImageScheduler.queue.length; index++) {
        const priority = ReaderImageScheduler.queue[index].priority();
        if (priority >= ReaderImageScheduler.BACKGROUND) {
          if (firstBackground < 0) firstBackground = index;
        } else if (firstForeground < 0 || priority < foregroundPriority) {
          firstForeground = index;
          foregroundPriority = priority;
          if (priority <= ReaderImageScheduler.VISIBLE) break;
        }
      }
      const foregroundBusy = firstForeground >= 0 ||
        ReaderImageScheduler.active > ReaderImageScheduler.activeBackground;
      const backgroundLimit = foregroundBusy ? ReaderImageScheduler.MAX_BACKGROUND :
        ReaderImageScheduler.MAX_BACKGROUND_IDLE;
      const background = firstForeground < 0;
      const best = background ?
        (ReaderImageScheduler.activeBackground < backgroundLimit ? firstBackground : -1) : firstForeground;
      if (best < 0) break;
      const ticket = ReaderImageScheduler.queue.splice(best, 1)[0];
      ReaderImageScheduler.active++;
      if (background) ReaderImageScheduler.activeBackground++;
      ticket.start(background);
    }
    ReaderImageScheduler.updatePurgeTimer();
  }

  /** 名额全被占着时也要及时放掉已取消的排队任务，切走章节后不必等慢图下完。 */
  private static purgeCancelled(): void {
    if (ReaderImageScheduler.queue.length === 0) return;
    const kept: ReaderImageTicket[] = [];
    for (const ticket of ReaderImageScheduler.queue) {
      if (ticket.cancelled()) ticket.reject(new Error(HttpClient.CANCELLED_ERROR));
      else kept.push(ticket);
    }
    ReaderImageScheduler.queue = kept;
  }

  private static updatePurgeTimer(): void {
    if (ReaderImageScheduler.queue.length > 0 && ReaderImageScheduler.purgeTimer < 0) {
      ReaderImageScheduler.purgeTimer = setInterval((): void => ReaderImageScheduler.pump(),
        ReaderImageScheduler.PURGE_INTERVAL_MS);
    } else if (ReaderImageScheduler.queue.length === 0 && ReaderImageScheduler.purgeTimer >= 0) {
      clearInterval(ReaderImageScheduler.purgeTimer);
      ReaderImageScheduler.purgeTimer = -1;
    }
  }
}

/** 一次正文请求里图片怎么处理：调度优先级，以及是否先返回待加载标记、图片在后台逐张处理。 */
export class ReaderImageRequest {
  static readonly DEFAULT: ReaderImageRequest = new ReaderImageRequest();
  priority: () => number = ReaderImageScheduler.foreground;
  /** 为 true 时正文先带着待加载标记返回，图片交给 ReaderImageResults 在后台逐张处理（阅读页的漫画模式）。 */
  deferred: boolean = false;
  /** 渐进模式下后台图片任务的取消条件。正文请求返回后图片仍要继续，所以与那次请求的取消分开。 */
  deferredCancelled: () => boolean = (): boolean => false;
}
