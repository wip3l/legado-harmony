import fs from '@ohos.file.fs';
import { appDb, CachedContentEntry } from '../../model/data/AppDatabase';
import { CacheBudgetItem, CacheBudgetPlan, ReaderCacheBudgetPolicy } from './ReaderCacheBudgetPolicy';

export class ReaderCacheCleanup {
  releasedBytes: number = 0;
  removed: number = 0;
  /** 正在使用而保留的条目数。 */
  protectedCount: number = 0;
  failed: number = 0;
}

/**
 * 小说正文缓存和漫画图片缓存的容量上限。
 * - 正文：超过上限时只清阅读、预缓存顺带写入的章节，手动缓存的章节和本地导入书的正文不动；
 * - 漫画：comic_images 目录按文件修改时间清理，命中缓存时会刷新修改时间。
 * 正在阅读的书、最近 10 分钟用过的缓存不参与自动清理。所有清理串行执行。
 */
export class ReaderCacheBudget {
  static readonly TEXT_LIMIT_BYTES: number = 256 * 1024 * 1024;
  static readonly COMIC_LIMIT_BYTES: number = 1024 * 1024 * 1024;
  private static readonly RECENT_PROTECT_MS: number = 10 * 60 * 1000;
  private static readonly TRIM_DELAY_MS: number = 15 * 1000;
  private static readonly COMIC_DIR_NAME: string = 'comic_images';
  private static protectedBooksProvider: () => string[] = (): string[] => [];
  private static chain: Promise<void> = Promise.resolve();
  private static textTimer: number = -1;
  private static comicTimer: number = -1;
  private static comicIndex: Map<string, CacheBudgetItem> = new Map();
  private static comicIndexDir: string = '';
  private static comicIndexAt: number = 0;
  private static readonly COMIC_RESCAN_MS: number = 5 * 60 * 1000;
  // Updated immediately, including while a directory scan is awaiting IO.
  private static comicRecentUses: Map<string, number> = new Map();

  /** 阅读引擎登记正在打开的书，清理时跳过这些书的正文。 */
  static setProtectedBooksProvider(provider: () => string[]): void {
    ReaderCacheBudget.protectedBooksProvider = provider;
  }

  static noteTextWrite(): void {
    if (ReaderCacheBudget.textTimer >= 0) return;
    ReaderCacheBudget.textTimer = setTimeout(() => {
      ReaderCacheBudget.textTimer = -1;
      ReaderCacheBudget.enqueue(() => ReaderCacheBudget.trimText()).catch(() => {});
    }, ReaderCacheBudget.TRIM_DELAY_MS);
  }

  static noteComicWrite(path?: string): void {
    if (path) ReaderCacheBudget.comicRecentUses.set(path, Date.now());
    ReaderCacheBudget.enqueue(async (): Promise<void> => {
      const dir = ReaderCacheBudget.comicDir();
      if (!path || !ReaderCacheBudget.isComicFile(path, dir)) {
        ReaderCacheBudget.comicIndexAt = 0;
        return;
      }
      // An initial scan will discover writes made before the index is ready.
      if (!ReaderCacheBudget.comicIndexAt || ReaderCacheBudget.comicIndexDir !== dir) return;
      try {
        const stat = await fs.stat(path);
        if (!stat.isFile()) { ReaderCacheBudget.comicIndexAt = 0; return; }
        const item = new CacheBudgetItem();
        item.id = path;
        item.bytes = stat.size;
        item.usedAt = Math.max(stat.mtime * 1000, ReaderCacheBudget.comicRecentUses.get(path) || 0);
        ReaderCacheBudget.comicIndex.set(path, item);
      } catch (_) {
        ReaderCacheBudget.comicIndexAt = 0;
      }
    }).catch(() => {});
    if (ReaderCacheBudget.comicTimer >= 0) return;
    ReaderCacheBudget.comicTimer = setTimeout(() => {
      ReaderCacheBudget.comicTimer = -1;
      ReaderCacheBudget.enqueue(() => ReaderCacheBudget.trimComic()).catch(() => {});
    }, ReaderCacheBudget.TRIM_DELAY_MS);
  }

  /** 启动后检查一次：升级前留下的缓存、上次没来得及清理的部分。 */
  static scheduleStartupTrim(delayMs: number = 20000): void {
    setTimeout(() => {
      ReaderCacheBudget.enqueue(async (): Promise<void> => {
        await ReaderCacheBudget.trimText();
        await ReaderCacheBudget.trimComic();
      }).catch(() => {});
    }, delayMs);
  }

  /** 命中漫画图片缓存时刷新修改时间，清理按最久未用的先删。 */
  static touchComicFile(path: string): void {
    const now = Date.now();
    ReaderCacheBudget.comicRecentUses.set(path, now);
    const item = ReaderCacheBudget.comicIndex.get(path);
    if (item) item.usedAt = now;
    try {
      fs.utimes(path, now);
    } catch (_) {
    }
  }

  static async textUsageBytes(): Promise<number> {
    return await ReaderCacheBudget.enqueueValue(async (): Promise<number> => {
      await ReaderCacheBudget.backfillTextBytes();
      return await appDb.getOnlineCachedContentBytes();
    });
  }

  static async comicUsageBytes(): Promise<number> {
    return await ReaderCacheBudget.enqueueValue(async (): Promise<number> => {
      let total = 0;
      for (const item of await ReaderCacheBudget.listComicFiles(true)) total += item.bytes;
      return total;
    });
  }

  /** 设置页的手动清理：清掉全部在线正文缓存（含手动缓存），正在阅读的书保留。本地导入书不受影响。 */
  static async clearText(): Promise<ReaderCacheCleanup> {
    return await ReaderCacheBudget.enqueueValue(async (): Promise<ReaderCacheCleanup> => {
      await ReaderCacheBudget.backfillTextBytes();
      const books = new Set<string>(ReaderCacheBudget.protectedBooksProvider());
      const items = ReaderCacheBudget.toTextItems(await appDb.listOnlineCachedContentEntries(false));
      const plan = ReaderCacheBudgetPolicy.planClear(items, (item: CacheBudgetItem): boolean => books.has(item.owner));
      return await ReaderCacheBudget.applyTextPlan(plan);
    });
  }

  static async clearComic(): Promise<ReaderCacheCleanup> {
    return await ReaderCacheBudget.enqueueValue(async (): Promise<ReaderCacheCleanup> => {
      const now = Date.now();
      const items = await ReaderCacheBudget.listComicFiles(true);
      const plan = ReaderCacheBudgetPolicy.planClear(items,
        (item: CacheBudgetItem): boolean => now - item.usedAt < ReaderCacheBudget.RECENT_PROTECT_MS);
      return ReaderCacheBudget.applyComicPlan(plan);
    });
  }

  private static async trimText(): Promise<void> {
    try {
      await ReaderCacheBudget.backfillTextBytes();
      const total = await appDb.getOnlineCachedContentBytes();
      if (total <= ReaderCacheBudget.TEXT_LIMIT_BYTES) return;
      const now = Date.now();
      const books = new Set<string>(ReaderCacheBudget.protectedBooksProvider());
      const items = ReaderCacheBudget.toTextItems(await appDb.listOnlineCachedContentEntries(true));
      const plan = ReaderCacheBudgetPolicy.planTrim(items, total, ReaderCacheBudget.TEXT_LIMIT_BYTES,
        (item: CacheBudgetItem): boolean =>
          books.has(item.owner) || now - item.usedAt < ReaderCacheBudget.RECENT_PROTECT_MS);
      const result = await ReaderCacheBudget.applyTextPlan(plan);
      console.info(`[ReaderCacheBudget] text trimmed removed=${result.removed} released=${result.releasedBytes} ` +
        `protected=${result.protectedCount} remaining=${plan.remainingBytes}`);
    } catch (e) {
      console.warn('[ReaderCacheBudget] text trim failed:', e);
    }
  }

  private static async trimComic(): Promise<void> {
    try {
      const items = await ReaderCacheBudget.listComicFiles();
      let total = 0;
      for (const item of items) total += item.bytes;
      if (total <= ReaderCacheBudget.COMIC_LIMIT_BYTES) return;
      const now = Date.now();
      const plan = ReaderCacheBudgetPolicy.planTrim(items, total, ReaderCacheBudget.COMIC_LIMIT_BYTES,
        (item: CacheBudgetItem): boolean => now - item.usedAt < ReaderCacheBudget.RECENT_PROTECT_MS);
      const result = ReaderCacheBudget.applyComicPlan(plan);
      console.info(`[ReaderCacheBudget] comic trimmed removed=${result.removed} released=${result.releasedBytes} ` +
        `protected=${result.protectedCount} failed=${result.failed}`);
    } catch (e) {
      console.warn('[ReaderCacheBudget] comic trim failed:', e);
    }
  }

  private static async backfillTextBytes(): Promise<void> {
    // 每批之间让出一次，升级后第一次统计也不会长时间占住数据库。
    while (await appDb.backfillCachedContentBytes() > 0) {
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 0);
      });
    }
  }

  private static toTextItems(entries: CachedContentEntry[]): CacheBudgetItem[] {
    return entries.map((entry: CachedContentEntry): CacheBudgetItem => {
      const item = new CacheBudgetItem();
      item.id = `${entry.rowId}`;
      item.owner = entry.bookUrl;
      item.bytes = entry.bytes;
      item.usedAt = entry.usedAt;
      return item;
    });
  }

  private static async applyTextPlan(plan: CacheBudgetPlan): Promise<ReaderCacheCleanup> {
    const result = new ReaderCacheCleanup();
    result.protectedCount = plan.protectedCount;
    if (plan.removeIds.length === 0) return result;
    try {
      await appDb.deleteCachedContentRows(plan.removeIds.map((id: string): number => Number(id)));
      result.removed = plan.removeIds.length;
      result.releasedBytes = plan.releasedBytes;
    } catch (e) {
      console.warn('[ReaderCacheBudget] delete text cache failed:', e);
      result.failed = plan.removeIds.length;
    }
    return result;
  }

  private static applyComicPlan(plan: CacheBudgetPlan): ReaderCacheCleanup {
    const result = new ReaderCacheCleanup();
    result.protectedCount = plan.protectedCount;
    for (const id of plan.removeIds) {
      // A cache hit or completed write may have arrived while the scan was suspended.
      if (Date.now() - (ReaderCacheBudget.comicRecentUses.get(id) || 0) < ReaderCacheBudget.RECENT_PROTECT_MS) {
        result.protectedCount++;
        continue;
      }
      try {
        const size = fs.statSync(id).size;
        fs.unlinkSync(id);
        ReaderCacheBudget.comicIndex.delete(id);
        ReaderCacheBudget.comicRecentUses.delete(id);
        result.removed++;
        result.releasedBytes += size;
      } catch (_) {
        ReaderCacheBudget.comicIndexAt = 0;
        result.failed++;
      }
    }
    return result;
  }

  private static comicDir(): string {
    const cacheDir = AppStorage.get<string>('appCacheDir') || '';
    return cacheDir ? `${cacheDir}/${ReaderCacheBudget.COMIC_DIR_NAME}` : '';
  }

  private static isComicFile(path: string, dir: string): boolean {
    if (!dir || !path.startsWith(`${dir}/`)) return false;
    const name = path.substring(dir.length + 1);
    return name.length > 0 && name !== '.' && name !== '..' && !/[\\/]/.test(name) && !/\.(tmp|part)$/.test(name);
  }

  private static async listComicFiles(force: boolean = false): Promise<CacheBudgetItem[]> {
    const items: CacheBudgetItem[] = [];
    const dir = ReaderCacheBudget.comicDir();
    if (!dir) return items;
    const now = Date.now();
    for (const [path, usedAt] of ReaderCacheBudget.comicRecentUses) {
      if (now - usedAt >= ReaderCacheBudget.RECENT_PROTECT_MS) ReaderCacheBudget.comicRecentUses.delete(path);
    }
    if (!force && ReaderCacheBudget.comicIndexDir === dir && ReaderCacheBudget.comicIndexAt > 0 &&
      now >= ReaderCacheBudget.comicIndexAt && now - ReaderCacheBudget.comicIndexAt < ReaderCacheBudget.COMIC_RESCAN_MS) {
      return Array.from(ReaderCacheBudget.comicIndex.values());
    }
    ReaderCacheBudget.comicIndexAt = 0;
    let names: string[] = [];
    try {
      if (!fs.accessSync(dir)) return items;
      names = await fs.listFile(dir);
    } catch (_) {
      return items;
    }
    for (const name of names) {
      const path = `${dir}/${name}`;
      if (!ReaderCacheBudget.isComicFile(path, dir)) continue;
      try {
        const stat = await fs.stat(path);
        if (!stat.isFile()) continue;
        const item = new CacheBudgetItem();
        item.id = path;
        item.bytes = stat.size;
        // mtime 是秒。
        item.usedAt = Math.max(stat.mtime * 1000, ReaderCacheBudget.comicRecentUses.get(path) || 0);
        items.push(item);
      } catch (_) {
      }
    }
    ReaderCacheBudget.comicIndex = new Map(items.map((item: CacheBudgetItem): [string, CacheBudgetItem] => [item.id, item]));
    ReaderCacheBudget.comicIndexDir = dir;
    ReaderCacheBudget.comicIndexAt = now;
    return items;
  }

  private static enqueue(task: () => Promise<void>): Promise<void> {
    const next = ReaderCacheBudget.chain.then(task, task);
    ReaderCacheBudget.chain = next.catch(() => {});
    return next;
  }

  private static enqueueValue<T>(task: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void): void => {
      ReaderCacheBudget.enqueue(async (): Promise<void> => {
        try {
          resolve(await task());
        } catch (e) {
          reject(e as Error);
        }
      }).catch(() => {});
    });
  }
}
