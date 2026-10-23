/** 路由仅携带短 ID，避免大幅 data: 图片超过路由参数上限；原图地址只在内存中短暂保留。 */
export class ComicTextRequests {
  private static sequence: number = 0;
  private static readonly pending: Map<string, string> = new Map();

  static put(source: string): string {
    const key = `comic_text_${++ComicTextRequests.sequence}`;
    ComicTextRequests.pending.set(key, source);
    while (ComicTextRequests.pending.size > 4) {
      for (const oldest of ComicTextRequests.pending.keys()) {
        ComicTextRequests.pending.delete(oldest);
        break;
      }
    }
    return key;
  }

  static take(key: string): string {
    const value = ComicTextRequests.pending.get(key) || '';
    ComicTextRequests.pending.delete(key);
    return value;
  }
}
