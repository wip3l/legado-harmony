export class ResponsiveManagerListLayout {
  private static readonly HORIZONTAL_PADDING: number = 32;
  private static readonly TARGET_COLUMN_WIDTH: number = 288;
  private static readonly COLUMN_GUTTER: number = 12;
  private static readonly MAX_LANES: number = 3;

  static laneCount(viewportWidth: number): number {
    const contentWidth = Math.max(1, viewportWidth - ResponsiveManagerListLayout.HORIZONTAL_PADDING);
    const fittedCount = Math.floor(
      (contentWidth + ResponsiveManagerListLayout.COLUMN_GUTTER) /
      (ResponsiveManagerListLayout.TARGET_COLUMN_WIDTH + ResponsiveManagerListLayout.COLUMN_GUTTER)
    );
    return Math.max(1, Math.min(ResponsiveManagerListLayout.MAX_LANES, fittedCount));
  }

  static gutter(viewportWidth: number): number {
    return ResponsiveManagerListLayout.laneCount(viewportWidth) > 1 ?
      ResponsiveManagerListLayout.COLUMN_GUTTER : 0;
  }
}
