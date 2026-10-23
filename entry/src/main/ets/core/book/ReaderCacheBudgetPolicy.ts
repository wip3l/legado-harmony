/** 一条可清理的缓存：正文缓存是数据库行号，漫画图片是文件路径。 */
export class CacheBudgetItem {
  id: string = '';
  /** 正文缓存所属的书；漫画图片为空。 */
  owner: string = '';
  bytes: number = 0;
  usedAt: number = 0;
}

export class CacheBudgetPlan {
  removeIds: string[] = [];
  releasedBytes: number = 0;
  protectedCount: number = 0;
  remainingBytes: number = 0;
}

/**
 * 缓存容量的清理计划，不做任何读写，便于在 Node 里回归。
 * 超过上限时按最久未用的先删，删到上限的 90% 为止，留出余量，免得每写一章都触发一次清理。
 */
export class ReaderCacheBudgetPolicy {
  static readonly TARGET_RATIO: number = 0.9;

  /**
   * totalBytes 是这类缓存的总量（可以包含不在 items 里、本来就不参与清理的部分，例如手动缓存的章节），
   * items 只放可以清理的条目。
   */
  static planTrim(items: CacheBudgetItem[], totalBytes: number, limitBytes: number,
    isProtected: (item: CacheBudgetItem) => boolean): CacheBudgetPlan {
    const plan = new CacheBudgetPlan();
    plan.remainingBytes = totalBytes;
    if (totalBytes <= limitBytes) return plan;
    const target = Math.floor(limitBytes * ReaderCacheBudgetPolicy.TARGET_RATIO);
    const ordered = [...items].sort((a: CacheBudgetItem, b: CacheBudgetItem): number => a.usedAt - b.usedAt);
    for (const item of ordered) {
      if (plan.remainingBytes <= target) break;
      if (isProtected(item)) {
        plan.protectedCount++;
        continue;
      }
      plan.removeIds.push(item.id);
      plan.releasedBytes += item.bytes;
      plan.remainingBytes -= item.bytes;
    }
    return plan;
  }

  /** 手动清理：除了正在使用的，全部删除。 */
  static planClear(items: CacheBudgetItem[], isProtected: (item: CacheBudgetItem) => boolean): CacheBudgetPlan {
    const plan = new CacheBudgetPlan();
    for (const item of items) {
      if (isProtected(item)) {
        plan.protectedCount++;
        plan.remainingBytes += item.bytes;
        continue;
      }
      plan.removeIds.push(item.id);
      plan.releasedBytes += item.bytes;
    }
    return plan;
  }

  static formatBytes(bytes: number): string {
    const value = Math.max(0, bytes);
    if (value >= 1024 * 1024 * 1024) return `${ReaderCacheBudgetPolicy.trimZero(value / 1024 / 1024 / 1024)} GiB`;
    if (value >= 1024 * 1024) return `${ReaderCacheBudgetPolicy.trimZero(value / 1024 / 1024)} MiB`;
    if (value >= 1024) return `${ReaderCacheBudgetPolicy.trimZero(value / 1024)} KiB`;
    return `${value} B`;
  }

  private static trimZero(value: number): string {
    const text = value >= 100 ? value.toFixed(0) : value.toFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
}
