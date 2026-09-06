export class ReaderV2Rect {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;

  constructor(left: number = 0, top: number = 0, right: number = 0, bottom: number = 0) {
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
  }

  width(): number {
    return Math.max(0, this.right - this.left);
  }

  height(): number {
    return Math.max(0, this.bottom - this.top);
  }

  contains(x: number, y: number, slopX: number = 0, slopY: number = 0): boolean {
    return x >= this.left - slopX && x <= this.right + slopX &&
      y >= this.top - slopY && y <= this.bottom + slopY;
  }
}

export class ReaderV2LayoutInput {
  viewportWidthPx: number = 0;
  viewportHeightPx: number = 0;
  safeTopPx: number = 0;
  safeBottomPx: number = 0;
  extendToStatusBar: boolean = false;
  marginLeftPx: number = 0;
  marginRightPx: number = 0;
  marginTopPx: number = 0;
  marginBottomPx: number = 0;
  bottomGuardPx: number = 0;
  columnGapPx: number = 0;
  columnCount: number = 1;
  fontSizePx: number = 40;
  titleFontSizePx: number = 44;
  lineSpacingPx: number = 0;
  paragraphSpacingPx: number = 0;
  letterSpacingPx: number = 0;
  textAlign: string = 'justify';
  bodyFontFamily: string = '';
  titleFontFamily: string = '';
  textColor: number = 0xFF202124;
  commentTextColor: number = 0xFF2A6FCC;
  commentBackgroundColor: number = 0x142A6FCC;
  commentRadiusPx: number = 12;
  commentFontSizePx: number = 30;
  commentHitSlopXPx: number = 16;
  commentHitSlopYPx: number = 12;
  commentsEnabled: boolean = true;
  regexEnabled: boolean = false;
  styleIdentity: string = '';
}

export class ReaderV2LayoutSnapshot {
  viewport: ReaderV2Rect = new ReaderV2Rect();
  contentRect: ReaderV2Rect = new ReaderV2Rect();
  columnRects: ReaderV2Rect[] = [];
  extendToStatusBar: boolean = false;
  fontSizePx: number = 40;
  titleFontSizePx: number = 44;
  lineSpacingPx: number = 0;
  paragraphSpacingPx: number = 0;
  letterSpacingPx: number = 0;
  textAlign: string = 'justify';
  bodyFontFamily: string = '';
  titleFontFamily: string = '';
  textColor: number = 0xFF202124;
  commentTextColor: number = 0xFF2A6FCC;
  commentBackgroundColor: number = 0x142A6FCC;
  commentRadiusPx: number = 12;
  commentFontSizePx: number = 30;
  commentHitSlopXPx: number = 16;
  commentHitSlopYPx: number = 12;
  commentsEnabled: boolean = true;
  regexEnabled: boolean = false;
  identity: string = '';

  static create(input: ReaderV2LayoutInput): ReaderV2LayoutSnapshot {
    const snapshot = new ReaderV2LayoutSnapshot();
    const width = Math.max(1, input.viewportWidthPx);
    const height = Math.max(1, input.viewportHeightPx);
    snapshot.viewport = new ReaderV2Rect(0, 0, width, height);
    snapshot.extendToStatusBar = input.extendToStatusBar;

    const safeTop = input.extendToStatusBar ? 0 : Math.max(0, input.safeTopPx);
    const safeBottom = input.extendToStatusBar ? 0 : Math.max(0, input.safeBottomPx);
    const left = Math.max(0, input.marginLeftPx);
    const top = safeTop + Math.max(0, input.marginTopPx);
    const right = Math.max(left + 1, width - Math.max(0, input.marginRightPx));
    const bottom = Math.max(top + 1, height - safeBottom - Math.max(0, input.bottomGuardPx) -
      Math.max(0, input.marginBottomPx));
    snapshot.contentRect = new ReaderV2Rect(left, top, right, bottom);

    const columnCount = Math.max(1, Math.min(2, Math.round(input.columnCount)));
    const gap = columnCount > 1 ? Math.max(0, input.columnGapPx) : 0;
    const columnWidth = Math.max(1, (snapshot.contentRect.width() - gap) / columnCount);
    for (let index = 0; index < columnCount; index++) {
      const columnLeft = snapshot.contentRect.left + index * (columnWidth + gap);
      snapshot.columnRects.push(new ReaderV2Rect(columnLeft, snapshot.contentRect.top,
        columnLeft + columnWidth, snapshot.contentRect.bottom));
    }

    snapshot.fontSizePx = Math.max(1, input.fontSizePx);
    snapshot.titleFontSizePx = Math.max(1, input.titleFontSizePx);
    snapshot.lineSpacingPx = Math.max(0, input.lineSpacingPx);
    snapshot.paragraphSpacingPx = Math.max(0, input.paragraphSpacingPx);
    snapshot.letterSpacingPx = input.letterSpacingPx;
    snapshot.textAlign = input.textAlign === 'start' || input.textAlign === 'end' ? input.textAlign : 'justify';
    snapshot.bodyFontFamily = input.bodyFontFamily;
    snapshot.titleFontFamily = input.titleFontFamily || input.bodyFontFamily;
    snapshot.textColor = input.textColor;
    snapshot.commentTextColor = input.commentTextColor;
    snapshot.commentBackgroundColor = input.commentBackgroundColor;
    snapshot.commentRadiusPx = Math.max(0, input.commentRadiusPx);
    snapshot.commentFontSizePx = Math.max(1, input.commentFontSizePx);
    snapshot.commentHitSlopXPx = Math.max(0, input.commentHitSlopXPx);
    snapshot.commentHitSlopYPx = Math.max(0, input.commentHitSlopYPx);
    snapshot.commentsEnabled = input.commentsEnabled;
    snapshot.regexEnabled = input.regexEnabled;
    snapshot.identity = ReaderV2LayoutSnapshot.buildIdentity(input, snapshot);
    return snapshot;
  }

  private static buildIdentity(input: ReaderV2LayoutInput, snapshot: ReaderV2LayoutSnapshot): string {
    const values = [
      snapshot.viewport.width(), snapshot.viewport.height(), snapshot.contentRect.left, snapshot.contentRect.top,
      snapshot.contentRect.right, snapshot.contentRect.bottom, snapshot.columnRects.length,
      snapshot.fontSizePx, snapshot.titleFontSizePx, snapshot.lineSpacingPx, snapshot.paragraphSpacingPx,
      snapshot.letterSpacingPx, snapshot.textAlign, snapshot.commentFontSizePx, snapshot.commentRadiusPx,
      snapshot.commentsEnabled ? 1 : 0, snapshot.regexEnabled ? 1 : 0
    ];
    const rounded = values.map((value: string | number): string =>
      typeof value === 'number' ? `${Math.round(value * 100) / 100}` : value).join('_');
    return `reader_layout_v2_${rounded}_${input.bodyFontFamily}_${input.titleFontFamily}_${input.styleIdentity}`;
  }
}
