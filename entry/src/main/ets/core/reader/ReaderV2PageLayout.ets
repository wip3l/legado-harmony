import graphicsText from '@ohos.graphics.text';
import { ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import { ReaderCommentBubbleStyle } from './ReaderCommentBubble';

/** Minimal native Text span metadata used by the transparent system-selection layer. */
export class ReaderV2SelectionRun {
  text: string = '';
  fontSizePx: number = 0;
  fontFamily: string = '';
  fontWeight: number = 400;
  letterSpacingPx: number = 0;

  constructor(text: string, fontSizePx: number, fontFamily: string, fontWeight: number,
    letterSpacingPx: number = 0) {
    this.text = text;
    this.fontSizePx = fontSizePx;
    this.fontFamily = fontFamily;
    this.fontWeight = fontWeight;
    this.letterSpacingPx = letterSpacingPx;
  }
}

export class ReaderV2RegexBubbleSegment {
  styleId: string = '';
  text: string = '';
  leading: boolean = false;
  trailing: boolean = false;
  rect: ReaderV2Rect = new ReaderV2Rect();
  capSizePx: number = 0;
  leadingCapWidthPx: number = 0;
  trailingCapWidthPx: number = 0;
  fontSizePx: number = 0;
  fontFamily: string = '';
  textColor: number = 0;
  backgroundColor: number = 0;
  radiusTopLeftPx: number = 0;
  radiusTopRightPx: number = 0;
  radiusBottomRightPx: number = 0;
  radiusBottomLeftPx: number = 0;
  shadowEnabled: boolean = false;
  shadowColor: number = 0;
  shadowRadiusPx: number = 0;
  shadowOffsetXPx: number = 0;
  shadowOffsetYPx: number = 0;
}

/** One line's piece of a paragraph-comment / 本章说 bubble; only the last piece carries the tail. */
export class ReaderV2CommentBubbleSegment {
  scale: number = 1;
  rect: ReaderV2Rect = new ReaderV2Rect();
  tail: boolean = true;
  style: ReaderCommentBubbleStyle = new ReaderCommentBubbleStyle();
}

export class ReaderV2PageFragment {
  blockId: string = '';
  blockIndex: number = 0;
  paragraph: graphicsText.Paragraph | null = null;
  paragraphX: number = 0;
  paragraphY: number = 0;
  clipRect: ReaderV2Rect = new ReaderV2Rect();
  localStart: number = 0;
  localEnd: number = 0;
  displayStart: number = 0;
  displayEnd: number = 0;
  paragraphHeight: number = 0;
  selectionPageStart: number = 0;
  selectionPageEnd: number = 0;
  /** 整页选中文本里，这个片段之后是否跟着一个换行（后面还有文字片段）。 */
  selectionBreakAfter: boolean = false;
  selectionRuns: ReaderV2SelectionRun[] = [];
  /** 图片片段：paragraph 为 null，图片以 Contain 方式绘制在 imageRect 内。 */
  imageSource: string = '';
  imageRect: ReaderV2Rect = new ReaderV2Rect();
  regexBubbleSegments: ReaderV2RegexBubbleSegment[] = [];
  commentBubbleSegments: ReaderV2CommentBubbleSegment[] = [];
}

export class ReaderV2ActionHitArea {
  actionId: string = '';
  marker: string = '';
  rect: ReaderV2Rect = new ReaderV2Rect();
}

export class ReaderV2PageLayout {
  pageIndex: number = 0;
  columnIndex: number = 0;
  displayStart: number = 0;
  displayEnd: number = 0;
  sourceStart: number = 0;
  sourceEnd: number = 0;
  contentRect: ReaderV2Rect = new ReaderV2Rect();
  fragments: ReaderV2PageFragment[] = [];
  actions: ReaderV2ActionHitArea[] = [];
  identity: string = '';
  selectionText: string = '';
  selectionX: number = 0;
  selectionY: number = 0;
  selectionWidth: number = 0;
  selectionHeight: number = 0;
  /** 本页最后一个片段的下边缘（含字形出血），滚动阅读用它确定列表项高度。 */
  contentBottomPx: number = 0;

  actionAt(x: number, y: number, slopX: number, slopY: number): ReaderV2ActionHitArea | null {
    // Later actions win where expanded hit slop overlaps, which matches visual painting order.
    for (let index = this.actions.length - 1; index >= 0; index--) {
      const action = this.actions[index];
      if (action.rect.contains(x, y, slopX, slopY)) return action;
    }
    return null;
  }
}

export class ReaderV2PageSet {
  documentIdentity: string = '';
  layoutIdentity: string = '';
  pages: ReaderV2PageLayout[] = [];
  complete: boolean = false;

  pageForDisplayOffset(offset: number): number {
    if (this.pages.length === 0) return 0;
    let low = 0;
    let high = this.pages.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.pages[middle].displayEnd <= offset) low = middle + 1;
      else high = middle;
    }
    return Math.max(0, Math.min(this.pages.length - 1, low));
  }
}
