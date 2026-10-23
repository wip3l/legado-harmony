import { ReaderImageMarker } from './ReaderImageMarker';
import { ReaderImageScheduler } from './ReaderImageScheduler';

class ReaderImageResultEntry {
  /** 本地路径或失败来源（ReaderImageMarker.failureSource）；还没有结果时为空串。 */
  source: string = '';
  inFlight: Promise<void> | null = null;
  listeners: ((source: string) => void)[] = [];
  visible: number = 0;
  near: number = 0;
}

/**
 * 渐进加载的正文图片按原始图片值登记处理结果。阅读器里的图片项订阅它，拿到结果就自己换图，
 * 不必改写章节正文或刷新列表；在屏幕上的图片登记为可见，调度时排在最前。
 */
export class ReaderImageResults {
  private static readonly LIMIT: number = 8192;
  private static entries: Map<string, ReaderImageResultEntry> = new Map<string, ReaderImageResultEntry>();

  /** 已有的结果；没有结果时为空串。 */
  static current(raw: string): string {
    const entry = ReaderImageResults.entries.get(raw);
    return entry ? entry.source : '';
  }

  /** 登记过且还有结果可等（已有结果或正在处理）。被清理或处理被取消的图片返回 false。 */
  static isAlive(raw: string): boolean {
    const entry = ReaderImageResults.entries.get(raw);
    return !!entry && (!!entry.source || !!entry.inFlight);
  }

  /**
   * 处理一张图片：同一张图同时只处理一次，处理中再次提交时等前一次；前一次被取消、没有结果才自己再处理。
   * job 返回本地路径或失败来源，取消时抛错、结果保持原样。返回的 Promise 不会失败。
   */
  static load(raw: string, job: () => Promise<string>): Promise<void> {
    const entry = ReaderImageResults.touch(raw);
    const previous = entry.inFlight;
    let task: Promise<void> | null = null;
    task = (async (): Promise<void> => {
      try {
        if (previous) {
          await previous;
          if (entry.source) return;
        }
        const source = await job();
        if (source) {
          entry.source = source;
          for (const listener of [...entry.listeners]) listener(source);
        }
      } catch (_) {
        // 取消：交给 finalize 发现这张图没有结果。
      } finally {
        if (entry.inFlight === task) entry.inFlight = null;
      }
    })();
    entry.inFlight = task;
    return task;
  }

  /** 订阅一张图的结果，返回取消订阅的函数。 */
  static subscribe(raw: string, listener: (source: string) => void): () => void {
    const entry = ReaderImageResults.touch(raw);
    entry.listeners.push(listener);
    return (): void => {
      const index = entry.listeners.indexOf(listener);
      if (index >= 0) entry.listeners.splice(index, 1);
    };
  }

  static setVisible(raw: string, visible: boolean): void {
    const entry = ReaderImageResults.entries.get(raw);
    if (entry) entry.visible = Math.max(0, entry.visible + (visible ? 1 : -1));
  }

  static isVisible(raw: string): boolean {
    const entry = ReaderImageResults.entries.get(raw);
    return !!entry && entry.visible > 0;
  }

  /** 已挂载在屏幕附近、马上可能看到的图片（条漫的缓存项、翻页模式后面几页）。 */
  static setNear(raw: string, near: boolean): void {
    const entry = ReaderImageResults.entries.get(raw);
    if (entry) entry.near = Math.max(0, entry.near + (near ? 1 : -1));
  }

  /** 这张图的调度优先级：屏幕上的最先，屏幕附近的其次，其余按 base。 */
  static priority(raw: string, base: () => number): number {
    const entry = ReaderImageResults.entries.get(raw);
    if (entry && entry.visible > 0) return ReaderImageScheduler.VISIBLE;
    if (entry && entry.near > 0) return ReaderImageScheduler.NEAR;
    return base();
  }

  /**
   * 等正文里的待加载图片都有了结果，返回换成最终来源的正文。有图片处理被取消、没有结果时返回空串。
   */
  static async finalize(text: string): Promise<string> {
    if (!ReaderImageMarker.hasPending(text)) return text;
    const prefix = ReaderImageMarker.PREFIX.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const suffix = ReaderImageMarker.SUFFIX.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const pattern = new RegExp(`${prefix}[^\\]]+${suffix}`, 'g');
    const markers = text.match(pattern) || [];
    for (const marker of markers) {
      const raw = ReaderImageMarker.pendingRaw(ReaderImageMarker.parse(marker).source);
      if (!raw) continue;
      const entry = ReaderImageResults.entries.get(raw);
      if (entry && entry.inFlight) await entry.inFlight;
      if (!ReaderImageResults.current(raw)) return '';
    }
    return text.replace(pattern, (marker: string): string => {
      const info = ReaderImageMarker.parse(marker);
      const raw = ReaderImageMarker.pendingRaw(info.source);
      return raw ? ReaderImageMarker.create(ReaderImageResults.current(raw), info.width, info.height) : marker;
    });
  }

  private static touch(raw: string): ReaderImageResultEntry {
    let entry = ReaderImageResults.entries.get(raw);
    if (entry) {
      ReaderImageResults.entries.delete(raw);
    } else {
      entry = new ReaderImageResultEntry();
    }
    ReaderImageResults.entries.set(raw, entry);
    ReaderImageResults.trim();
    return entry;
  }

  /** 超出上限时从最久没用的开始清理，正在处理、有人订阅或在屏幕上及附近的不清理。 */
  private static trim(): void {
    if (ReaderImageResults.entries.size <= ReaderImageResults.LIMIT) return;
    for (const item of [...ReaderImageResults.entries]) {
      if (ReaderImageResults.entries.size <= ReaderImageResults.LIMIT) return;
      const entry = item[1];
      if (!entry.inFlight && entry.listeners.length === 0 && entry.visible === 0 && entry.near === 0) {
        ReaderImageResults.entries.delete(item[0]);
      }
    }
  }
}
