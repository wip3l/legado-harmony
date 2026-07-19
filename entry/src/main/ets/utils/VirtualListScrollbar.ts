export class VirtualListScrollbar {
  static thumbLength(viewportHeight: number, totalCount: number, visibleCount: number,
    minimumLength: number = 24): number {
    const viewport = Math.max(0, viewportHeight);
    if (viewport <= 0 || totalCount <= 0) return 0;
    const visible = Math.max(1, Math.min(visibleCount, totalCount));
    return Math.min(viewport, Math.max(minimumLength, viewport * visible / totalCount));
  }

  static thumbOffset(viewportHeight: number, thumbLength: number, totalCount: number,
    firstVisibleIndex: number, visibleCount: number): number {
    const travel = Math.max(0, viewportHeight - thumbLength);
    const maxFirstIndex = Math.max(0, totalCount - Math.max(1, visibleCount));
    if (travel <= 0 || maxFirstIndex <= 0) return 0;
    const first = Math.max(0, Math.min(firstVisibleIndex, maxFirstIndex));
    return travel * first / maxFirstIndex;
  }
}
