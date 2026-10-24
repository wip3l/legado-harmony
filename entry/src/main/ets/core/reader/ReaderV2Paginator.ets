import graphicsText from '@ohos.graphics.text';
import common2D from '@ohos.graphics.common2D';
import { ReaderV2Block, ReaderV2Document, ReaderV2InlineAction } from './ReaderV2Document';
import { ReaderV2LayoutSnapshot, ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import {
  ReaderV2ActionHitArea,
  ReaderV2PageFragment,
  ReaderV2PageLayout,
  ReaderV2PageSet,
  ReaderV2CommentBubbleSegment,
  ReaderV2RegexBubbleSegment,
  ReaderV2SelectionRun
} from './ReaderV2PageLayout';
import { ReaderV2SpanStyleRange } from './ReaderV2Style';
import { ReaderCommentBubbleSize } from './ReaderCommentBubbleSize';
import { ReaderCommentBubblePainter } from './ReaderCommentBubble';
import { ReaderMixedPageLayout } from './ReaderMixedPageLayout';

class ReaderV2MeasuredBlock {
  block: ReaderV2Block;
  paragraph: graphicsText.Paragraph;
  lines: graphicsText.LineMetrics[];

  constructor(block: ReaderV2Block, paragraph: graphicsText.Paragraph, lines: graphicsText.LineMetrics[]) {
    this.block = block;
    this.paragraph = paragraph;
    this.lines = lines;
  }
}

/** Retains native paragraph measurements so pagination can continue in small UI-thread slices. */
export class ReaderV2PaginationSession {
  document: ReaderV2Document;
  snapshot: ReaderV2LayoutSnapshot;
  regexStyles: ReaderV2SpanStyleRange[];
  pageSet: ReaderV2PageSet = new ReaderV2PageSet();
  width: number = 0;
  blockIndex: number = 0;
  lineIndex: number = 0;
  pageIndex: number = 0;
  measuredBlock: ReaderV2MeasuredBlock | null = null;
  /** 整章只有图片（封面页、插图页）：整页插图铺满页面，不留正文边距。 */
  imageOnly: boolean = false;
  /** 滚动阅读：整份文档排成一页，不受页高限制。 */
  continuous: boolean = false;
  private blockStyles: ReaderV2SpanStyleRange[] = [];
  private blockStylesIndex: number = -1;

  /**
   * Regex styles overlapping the current block, in their original order. Every style lookup below is
   * block-local, so scanning the whole chapter's styles per boundary made pagination O(blocks × styles).
   */
  currentBlockStyles(): ReaderV2SpanStyleRange[] {
    if (this.regexStyles.length === 0) return this.regexStyles;
    if (this.blockStylesIndex !== this.blockIndex) {
      const block = this.document.blocks[this.blockIndex];
      const blockEnd = block.displayStart + block.text.length;
      this.blockStyles = this.regexStyles.filter((style: ReaderV2SpanStyleRange): boolean =>
        style.end > block.displayStart && style.start < blockEnd);
      this.blockStylesIndex = this.blockIndex;
    }
    return this.blockStyles;
  }

  constructor(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[]) {
    this.document = document;
    this.snapshot = snapshot;
    this.regexStyles = regexStyles;
    this.pageSet.documentIdentity = document.identity;
    this.pageSet.layoutIdentity = snapshot.identity;
    this.width = snapshot.columnRects.length > 0 ? snapshot.columnRects[0].width() : 0;
    this.pageSet.complete = document.blocks.length === 0 || snapshot.columnRects.length === 0;
    this.imageOnly = document.blocks.length > 0 &&
      document.blocks.every((block: ReaderV2Block): boolean => !!block.image);
  }
}

export class ReaderV2Paginator {
  /** Measures a plain selectable surface with the same native paragraph engine as pagination. */
  static glyphPositionForPlainText(text: string, snapshot: ReaderV2LayoutSnapshot,
    width: number, x: number, y: number): number {
    if (!text) return 0;
    const document = new ReaderV2Document();
    document.sourceText = text;
    document.displayText = text;
    const block = new ReaderV2Block('selection', text, 0, text.length, 0, text.length, false);
    const paragraph = ReaderV2Paginator.buildParagraph(document, block, snapshot, [], Math.max(1, width),
      0, text.length);
    return paragraph.getGlyphPositionAtCoordinate(Math.max(0, x), Math.max(0, y)).position;
  }

  static paginate(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[] = []): ReaderV2PageSet {
    const session = ReaderV2Paginator.start(document, snapshot, regexStyles);
    while (!session.pageSet.complete) {
      const appended = ReaderV2Paginator.appendPages(session, 32);
      if (appended <= 0) break;
    }
    return session.pageSet;
  }

  /**
   * Lays the whole document out as one unbounded column for continuous scrolling. The caller sizes its
   * list item from contentBottomPx; every other field has the same meaning as on a paged layout.
   */
  static layoutContinuous(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[] = []): ReaderV2PageLayout | null {
    const session = new ReaderV2PaginationSession(document, snapshot, regexStyles);
    session.continuous = true;
    ReaderV2Paginator.appendPages(session, 1);
    return session.pageSet.pages.length > 0 ? session.pageSet.pages[0] : null;
  }

  static start(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[] = []): ReaderV2PaginationSession {
    return new ReaderV2PaginationSession(document, snapshot, regexStyles);
  }

  static appendPages(session: ReaderV2PaginationSession, maxPages: number): number {
    const result = session.pageSet;
    if (result.complete || maxPages <= 0 || session.snapshot.columnRects.length === 0) return 0;
    const limit = Math.max(1, Math.round(maxPages));
    let appended = 0;
    while (session.blockIndex < session.document.blocks.length && appended < limit) {
      const columnIndex = session.pageIndex % session.snapshot.columnRects.length;
      const column = session.snapshot.columnRects[columnIndex];
      const page = new ReaderV2PageLayout();
      page.pageIndex = session.pageIndex;
      page.columnIndex = columnIndex;
      page.contentRect = new ReaderV2Rect(column.left, column.top, column.right, column.bottom);
      const columnBottom = session.continuous ? Number.MAX_SAFE_INTEGER : column.bottom;
      let y = column.top;
      let hasContent = false;
      let topInkGuardApplied = false;
      let mustEndPage = false;
      let previousWasImage = false;
      // Index of the first hit area each fragment contributed, so fragments can be moved with their areas.
      const fragmentActionStarts: number[] = [];

      while (session.blockIndex < session.document.blocks.length && !mustEndPage) {
        const imageBlock = session.document.blocks[session.blockIndex];
        if (imageBlock.image) {
          // Image sizing rules live in ReaderMixedPageLayout: small images flow with the text at
          // their natural size; illustrations and images of unknown size fill the rest of the page and end it.
          const gap = hasContent ? ReaderV2Paginator.imageGap(session.snapshot) : 0;
          const remaining = columnBottom - y - gap;
          const natural = ReaderMixedPageLayout.naturalBoxForSize(imageBlock.image.width, imageBlock.image.height,
            session.width, column.height(), session.snapshot.imagePxPerVp);
          let imageRect: ReaderV2Rect;
          let endsPage = false;
          if (natural && !natural.fill) {
            if (hasContent && natural.heightPx > remaining + 0.01) {
              mustEndPage = true;
              continue;
            }
            const left = column.left + Math.max(0, (session.width - natural.widthPx) / 2);
            imageRect = new ReaderV2Rect(left, y + gap, left + natural.widthPx, y + gap + natural.heightPx);
          } else {
            const wanted = natural ?
              Math.min(natural.heightPx, column.height()) * ReaderMixedPageLayout.FILL_MIN_RATIO : 0;
            if (!session.continuous && hasContent &&
              remaining < Math.max(session.snapshot.imageMinHeightPx, wanted)) {
              mustEndPage = true;
              continue;
            }
            const viewport = session.snapshot.viewport;
            if (session.continuous) {
              const height = natural ? Math.min(natural.heightPx, column.height()) :
                session.width * ReaderV2Paginator.CONTINUOUS_UNKNOWN_IMAGE_ASPECT;
              imageRect = new ReaderV2Rect(column.left, y + gap, column.right, y + gap + height);
            } else {
              imageRect = session.imageOnly && !hasContent ?
                new ReaderV2Rect(viewport.left, viewport.top, viewport.right, columnBottom) :
                new ReaderV2Rect(column.left, y + gap, column.right, columnBottom);
              endsPage = true;
            }
          }
          const imageFragment = new ReaderV2PageFragment();
          imageFragment.blockId = imageBlock.id;
          imageFragment.blockIndex = session.blockIndex;
          imageFragment.imageSource = imageBlock.image.source;
          imageFragment.imageRect = imageRect;
          imageFragment.paragraphX = imageRect.left;
          imageFragment.paragraphY = imageRect.top;
          imageFragment.paragraphHeight = imageRect.height();
          imageFragment.clipRect = imageRect;
          imageFragment.localStart = 0;
          imageFragment.localEnd = imageBlock.text.length;
          imageFragment.displayStart = imageBlock.displayStart;
          imageFragment.displayEnd = imageBlock.displayEnd;
          fragmentActionStarts.push(page.actions.length);
          page.fragments.push(imageFragment);
          if (!hasContent) page.displayStart = imageFragment.displayStart;
          page.displayEnd = imageFragment.displayEnd;
          hasContent = true;
          previousWasImage = true;
          y = imageRect.bottom;
          session.blockIndex++;
          session.lineIndex = 0;
          session.measuredBlock = null;
          mustEndPage = endsPage;
          continue;
        }

        let current = session.measuredBlock;
        if (!current || current.block !== session.document.blocks[session.blockIndex]) {
          current = ReaderV2Paginator.measureBlock(session.document, session.document.blocks[session.blockIndex],
            session.snapshot, session.currentBlockStyles(), session.width);
          session.measuredBlock = current;
        }
        if (current.lines.length === 0) {
          session.blockIndex++;
          session.lineIndex = 0;
          session.measuredBlock = null;
          continue;
        }

        const startsNewBlock = session.lineIndex === 0;
        const spacing = startsNewBlock && hasContent ? Math.max(session.snapshot.paragraphSpacingPx,
          previousWasImage ? ReaderV2Paginator.imageGap(session.snapshot) : 0) : 0;
        const firstLine = current.lines[session.lineIndex];
        if (!hasContent && !topInkGuardApplied) {
          // A zero user margin places the first logical line box on the page boundary. Some fonts (notably the
          // serif family used by several themes) paint one or two physical pixels above that logical box. The
          // render node cannot draw outside its own surface, so those pixels used to be clipped. Reserve exactly
          // the measured ink overflow plus one anti-alias pixel: the visible glyph still starts at the user's
          // requested boundary, while the setting itself remains theme-independent.
          y += ReaderV2Paginator.lineTopInkGuard(firstLine);
          topInkGuardApplied = true;
        }
        const firstLineHeight = ReaderV2Paginator.lineBottom(firstLine) - firstLine.topHeight;
        if (hasContent && y + spacing + firstLineHeight > columnBottom + 0.01) {
          // Paragraph spacing belongs to the next block. It is never consumed as invisible page-tail space.
          break;
        }
        y += spacing;

        const fragmentFirstLine = session.lineIndex;
        const paragraphLineTop = current.lines[fragmentFirstLine].topHeight;
        let fragmentLastLine = fragmentFirstLine - 1;
        let fragmentBottom = paragraphLineTop;
        while (session.lineIndex < current.lines.length) {
          const line = current.lines[session.lineIndex];
          const relativeBottom = ReaderV2Paginator.lineBottom(line) - paragraphLineTop;
          if (y + relativeBottom > columnBottom + 0.01 && fragmentLastLine >= fragmentFirstLine) break;
          // A single oversized line still owns an otherwise empty page, preventing a pagination dead loop.
          if (y + relativeBottom > columnBottom + 0.01 && hasContent) break;
          fragmentLastLine = session.lineIndex;
          fragmentBottom = ReaderV2Paginator.lineBottom(line);
          session.lineIndex++;
          if (y + relativeBottom >= columnBottom - 0.01) break;
        }

        if (fragmentLastLine < fragmentFirstLine) {
          mustEndPage = hasContent;
          if (mustEndPage) continue;
          fragmentLastLine = fragmentFirstLine;
          fragmentBottom = ReaderV2Paginator.lineBottom(current.lines[fragmentFirstLine]);
          session.lineIndex = fragmentFirstLine + 1;
        }

        const fragment = ReaderV2Paginator.createFragment(session.document, current, session.blockIndex,
          fragmentFirstLine, fragmentLastLine, column.left, y, paragraphLineTop, fragmentBottom,
          session.snapshot, session.currentBlockStyles(), session.width);
        fragmentActionStarts.push(page.actions.length);
        page.fragments.push(fragment);
        ReaderV2Paginator.appendActionAreas(page, fragment, session.document.actions, session.snapshot);
        if (!hasContent) page.displayStart = fragment.displayStart;
        page.displayEnd = fragment.displayEnd;
        hasContent = true;
        previousWasImage = false;
        y += fragmentBottom - paragraphLineTop;

        if (session.lineIndex >= current.lines.length) {
          session.blockIndex++;
          session.lineIndex = 0;
          session.measuredBlock = null;
        } else {
          mustEndPage = true;
        }
      }

      if (!hasContent) break;
      if (!session.continuous && session.blockIndex < session.document.blocks.length) {
        // More of the chapter follows, so this page ended because the next line did not fit.
        ReaderV2Paginator.alignPageBottom(page, fragmentActionStarts, column.bottom - y, session.snapshot);
      }
      ReaderV2Paginator.finalizePageSelection(page);
      for (const fragment of page.fragments) {
        page.contentBottomPx = Math.max(page.contentBottomPx, fragment.clipRect.bottom);
      }
      page.sourceStart = session.document.sourceOffsetForDisplay(page.displayStart);
      page.sourceEnd = session.document.sourceOffsetForDisplay(page.displayEnd);
      page.identity = `${session.document.identity}_${session.snapshot.identity}_${session.pageIndex}_` +
        `${page.displayStart}_${page.displayEnd}`;
      result.pages.push(page);
      session.pageIndex++;
      appended++;
    }
    result.complete = session.blockIndex >= session.document.blocks.length;
    return appended;
  }

  /**
   * 页底对齐：一页排满后底部通常剩不到一行的空白，每页剩的还不一样。把这点空白均分到本页各块之间，
   * 让末行落在版心底边。只调整块间距，不动行距和断行；每个间隙最多加半个字高，
   * 块太少摊不完时保留剩余空白，避免段间距被拉得突兀。
   */
  private static alignPageBottom(page: ReaderV2PageLayout, fragmentActionStarts: number[], leftoverPx: number,
    snapshot: ReaderV2LayoutSnapshot): void {
    const gaps = page.fragments.length - 1;
    // 剩余超过两行说明这一页是被整页插图或放不下的大块提前结束的，不属于要对齐的情况。
    if (gaps <= 0 || leftoverPx <= 0.5 || leftoverPx > (snapshot.fontSizePx + snapshot.lineSpacingPx) * 2) return;
    const perGapPx = Math.min(leftoverPx / gaps, snapshot.fontSizePx * 0.5);
    for (let index = 1; index < page.fragments.length; index++) {
      const shiftPx = perGapPx * index;
      const fragment = page.fragments[index];
      fragment.paragraphY += shiftPx;
      fragment.clipRect.top += shiftPx;
      fragment.clipRect.bottom += shiftPx;
      if (fragment.imageRect !== fragment.clipRect) {
        fragment.imageRect.top += shiftPx;
        fragment.imageRect.bottom += shiftPx;
      }
      for (const segment of fragment.regexBubbleSegments) {
        segment.rect.top += shiftPx;
        segment.rect.bottom += shiftPx;
      }
      for (const bubble of fragment.commentBubbleSegments) {
        bubble.rect.top += shiftPx;
        bubble.rect.bottom += shiftPx;
      }
      const actionEnd = index + 1 < fragmentActionStarts.length ? fragmentActionStarts[index + 1] :
        page.actions.length;
      for (let actionIndex = fragmentActionStarts[index]; actionIndex < actionEnd; actionIndex++) {
        page.actions[actionIndex].rect.top += shiftPx;
        page.actions[actionIndex].rect.bottom += shiftPx;
      }
    }
  }

  /** 滚动阅读里尺寸未知的图片按 高/宽 = 这个比例占位。 */
  private static readonly CONTINUOUS_UNKNOWN_IMAGE_ASPECT: number = 0.62;

  /** Vertical gap between an image block and neighbouring text, even when paragraph spacing is zero. */
  private static imageGap(snapshot: ReaderV2LayoutSnapshot): number {
    return Math.max(snapshot.paragraphSpacingPx, snapshot.lineSpacingPx, snapshot.fontSizePx * 0.5);
  }

  private static measureBlock(document: ReaderV2Document, block: ReaderV2Block,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[], width: number): ReaderV2MeasuredBlock {
    const paragraph = ReaderV2Paginator.buildParagraph(document, block, snapshot, regexStyles, width,
      0, block.text.length);
    return new ReaderV2MeasuredBlock(block, paragraph, paragraph.getLineMetrics());
  }

  private static buildParagraph(document: ReaderV2Document, block: ReaderV2Block,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[], width: number,
    sliceStart: number, sliceEnd: number): graphicsText.Paragraph {
    const baseStyle = ReaderV2Paginator.baseTextStyle(block, snapshot);
    const paragraphStyle: graphicsText.ParagraphStyle = {
      textStyle: baseStyle,
      align: ReaderV2Paginator.textAlign(snapshot.textAlign),
      textDirection: graphicsText.TextDirection.LTR,
      wordBreak: graphicsText.WordBreak.BREAK_WORD,
      breakStrategy: graphicsText.BreakStrategy.GREEDY,
      trailingSpaceOptimized: true,
      lineSpacing: snapshot.lineSpacingPx,
      // A paragraph is painted independently for every source block. With font padding disabled, glyph ink from
      // some CJK families can extend above the first logical line box and be clipped by Paragraph itself. Later
      // lines appear intact because their preceding line spacing provides bleed room. Include the native font
      // padding so the first-row ink is part of the measured paragraph; pagination consumes the same metrics.
      includeFontPadding: true
    };
    const builder = new graphicsText.ParagraphBuilder(paragraphStyle,
      graphicsText.FontCollection.getGlobalInstance());
    const safeStart = Math.max(0, Math.min(block.text.length, sliceStart));
    const safeEnd = Math.max(safeStart, Math.min(block.text.length, sliceEnd));
    const boundaries = ReaderV2Paginator.styleBoundaries(document, block, regexStyles, safeStart, safeEnd);
    for (let index = 0; index < boundaries.length - 1; index++) {
      const start = boundaries[index];
      const end = boundaries[index + 1];
      if (end <= start) continue;
      const absoluteStart = block.displayStart + start;
      const style = ReaderV2Paginator.styleAt(document, block, absoluteStart, snapshot, regexStyles);
      builder.pushStyle(style);
      builder.addText(block.text.substring(start, end));
      builder.popStyle();
    }
    const paragraph = builder.build();
    paragraph.layoutSync(width);
    return paragraph;
  }

  private static textAlign(value: string): graphicsText.TextAlign {
    if (value === 'start') return graphicsText.TextAlign.LEFT;
    if (value === 'end') return graphicsText.TextAlign.RIGHT;
    return graphicsText.TextAlign.JUSTIFY;
  }

  private static readonly FONT_WEIGHTS: graphicsText.FontWeight[] = [
      graphicsText.FontWeight.W100, graphicsText.FontWeight.W200,
      graphicsText.FontWeight.W300, graphicsText.FontWeight.W400, graphicsText.FontWeight.W500,
      graphicsText.FontWeight.W600, graphicsText.FontWeight.W700, graphicsText.FontWeight.W800,
      graphicsText.FontWeight.W900];

  private static bodyFontWeight(weight: number): graphicsText.FontWeight {
    // Static faces use the nearest SDK weight; the wght axis below preserves precise variable-font values.
    return ReaderV2Paginator.FONT_WEIGHTS[Math.max(0, Math.min(8, Math.round(weight / 100) - 1))];
  }

  private static baseTextStyle(block: ReaderV2Block, snapshot: ReaderV2LayoutSnapshot): graphicsText.TextStyle {
    const heading = block.title || block.headingLevel > 0;
    // Chapter titles keep the user's title size. In-chapter headings sit between body and title size so a
    // deep heading never outweighs the chapter title; level 3+ only gains the title face and weight.
    const headingFontSizePx = block.headingLevel > 2 ? snapshot.fontSizePx :
      Math.max(snapshot.fontSizePx, (snapshot.fontSizePx + snapshot.titleFontSizePx) / 2);
    return {
      fontSize: block.title ? snapshot.titleFontSizePx : (heading ? headingFontSizePx : snapshot.fontSizePx),
      letterSpacing: snapshot.letterSpacingPx,
      fontFamilies: [heading ? snapshot.titleFontFamily : snapshot.bodyFontFamily],
      fontWeight: heading ? graphicsText.FontWeight.W600 : ReaderV2Paginator.bodyFontWeight(snapshot.fontWeight),
      fontVariations: [{ axis: 'wght', value: heading ? 600 : snapshot.fontWeight }],
      color: ReaderV2Paginator.graphicsColor(snapshot.textColor),
      halfLeading: false,
      heightOnly: true,
      heightScale: 1,
      locale: 'zh-Hans'
    };
  }

  private static styleBoundaries(document: ReaderV2Document, block: ReaderV2Block,
    regexStyles: ReaderV2SpanStyleRange[], sliceStart: number = 0,
    sliceEnd: number = block.text.length): number[] {
    const boundaries: number[] = [sliceStart, sliceEnd];
    const absoluteSliceStart = block.displayStart + sliceStart;
    const absoluteSliceEnd = block.displayStart + sliceEnd;
    const firstAction = ReaderV2Paginator.firstActionWhoseEndExceeds(document.actions, absoluteSliceStart);
    for (let index = firstAction; index < document.actions.length; index++) {
      const action = document.actions[index];
      if (action.displayStart >= absoluteSliceEnd) break;
      const actionStart = action.displayStart - block.displayStart;
      const actionEnd = action.displayEnd - block.displayStart;
      if (actionEnd <= sliceStart || actionStart >= sliceEnd) continue;
      boundaries.push(Math.max(sliceStart, actionStart));
      boundaries.push(Math.min(sliceEnd, actionEnd));
    }
    for (const style of regexStyles) {
      const styleStart = style.start - block.displayStart;
      const styleEnd = style.end - block.displayStart;
      if (styleEnd <= sliceStart || styleStart >= sliceEnd) continue;
      boundaries.push(Math.max(sliceStart, styleStart));
      boundaries.push(Math.min(sliceEnd, styleEnd));
      if (style.decorationEnabled && style.decorationSizePx > 0) {
        // Isolate the character that owns each decoration reservation. Letter spacing is applied after a
        // character, so the character immediately before the run owns the leading gap and the run's last
        // character owns the trailing gap. No synthetic text is inserted and source/selection offsets stay exact.
        const leadingOwner = styleStart - 1;
        if (leadingOwner >= sliceStart && leadingOwner < sliceEnd) {
          boundaries.push(leadingOwner);
          boundaries.push(Math.min(sliceEnd, leadingOwner + 1));
        }
        const trailingOwner = styleEnd - 1;
        if (trailingOwner >= sliceStart && trailingOwner < sliceEnd) {
          boundaries.push(trailingOwner);
          boundaries.push(Math.min(sliceEnd, trailingOwner + 1));
        }
      }
    }
    boundaries.sort((left: number, right: number): number => left - right);
    const unique: number[] = [];
    for (const value of boundaries) {
      if (unique.length === 0 || unique[unique.length - 1] !== value) unique.push(value);
    }
    return unique;
  }

  private static styleAt(document: ReaderV2Document, block: ReaderV2Block, absoluteOffset: number,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[]): graphicsText.TextStyle {
    const base = ReaderV2Paginator.baseTextStyle(block, snapshot);
    const decorationReservation = ReaderV2Paginator.decorationReservationAfter(absoluteOffset, block, regexStyles);
    if (decorationReservation > 0) base.letterSpacing = snapshot.letterSpacingPx + decorationReservation;
    const actionIndex = ReaderV2Paginator.firstActionWhoseEndExceeds(document.actions, absoluteOffset);
    if (actionIndex < document.actions.length) {
      const action = document.actions[actionIndex];
      if (absoluteOffset >= action.displayStart && absoluteOffset < action.displayEnd) {
        const scale = ReaderCommentBubbleSize.scale(action.label, snapshot.commentBubbleSize);
        base.fontSize = snapshot.commentFontSizePx * scale;
        base.letterSpacing = snapshot.letterSpacingPx * scale;
        // The bubble behind the label is painted by the page node, not as a text background.
        base.color = ReaderV2Paginator.graphicsColor(snapshot.commentBubble.text);
        return base;
      }
    }
    for (const style of regexStyles) {
      if (absoluteOffset < style.start || absoluteOffset >= style.end) continue;
      if (style.fontSizePx > 0) base.fontSize = style.fontSizePx;
      if (style.fontFamily) base.fontFamilies = [style.fontFamily];
      if (style.color !== 0) base.color = ReaderV2Paginator.graphicsColor(style.color);
      if (style.backgroundEnabled && !style.decorationEnabled) {
        base.backgroundRect = {
          color: ReaderV2Paginator.graphicsColor(style.backgroundColor),
          leftTopRadius: style.radiusTopLeftPx,
          rightTopRadius: style.radiusTopRightPx,
          rightBottomRadius: style.radiusBottomRightPx,
          leftBottomRadius: style.radiusBottomLeftPx
        };
      }
      if (style.shadowEnabled && !style.decorationEnabled) {
        base.textShadows = [{
          color: ReaderV2Paginator.graphicsColor(style.shadowColor),
          point: { x: Math.max(0, style.shadowOffsetXPx), y: Math.max(0, style.shadowOffsetYPx) },
          blurRadius: style.shadowRadiusPx
        }];
      }
      // Keep decorated text in the native paragraph. The decoration is painted as a background layer by
      // ReadBook, while this paragraph remains the single source of truth for glyph metrics and baselines.
      // Repainting the text in an ArkUI Text containing ImageSpans gives that copy a different line box and
      // makes decorated and ordinary text on the same line visibly drift vertically.
      return base;
    }
    return base;
  }

  private static decorationReservationAfter(absoluteOffset: number, block: ReaderV2Block,
    regexStyles: ReaderV2SpanStyleRange[]): number {
    let reservation = 0;
    const blockStart = block.displayStart;
    const blockEnd = block.displayStart + block.text.length;
    for (const style of regexStyles) {
      if (!style.decorationEnabled || style.decorationSizePx <= 0 || style.end <= blockStart ||
        style.start >= blockEnd) continue;
      // The leading cap uses spacing after the preceding character. At a true paragraph boundary there is no
      // preceding glyph, so the painter clips that cap to the content edge instead of moving source offsets.
      if (style.start > blockStart && absoluteOffset === style.start - 1) {
        reservation = Math.max(reservation, style.decorationSizePx);
      }
      if (absoluteOffset === style.end - 1) {
        reservation = Math.max(reservation, style.decorationSizePx);
      }
    }
    return reservation;
  }

  private static createFragment(document: ReaderV2Document, current: ReaderV2MeasuredBlock,
    blockIndex: number, firstLine: number,
    lastLine: number, x: number, y: number, paragraphLineTop: number,
    paragraphLineBottom: number, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[], width: number): ReaderV2PageFragment {
    const first = current.lines[firstLine];
    const last = current.lines[lastLine];
    const fragment = new ReaderV2PageFragment();
    fragment.blockId = current.block.id;
    fragment.blockIndex = blockIndex;
    // Render only the lines owned by this page. Painting the full block and clipping at a line metric boundary
    // cuts italic/anti-aliased ink at the top and may expose one or two pixels of the next line at the bottom.
    // A page-local paragraph contains no neighbouring lines, so a small ink bleed is safe and layout-neutral.
    // A block that fits on the page whole is the common case: its measured paragraph already is that
    // page-local paragraph, so laying the same text out a second time is skipped.
    const wholeBlock = firstLine === 0 && lastLine === current.lines.length - 1 &&
      first.startIndex === 0 && last.endIndex === current.block.text.length;
    fragment.paragraph = wholeBlock ? current.paragraph :
      ReaderV2Paginator.buildParagraph(document, current.block, snapshot, regexStyles, width,
        first.startIndex, last.endIndex);
    fragment.selectionRuns = ReaderV2Paginator.buildSelectionRuns(document, current.block, snapshot, regexStyles,
      first.startIndex, last.endIndex);
    fragment.paragraphX = x;
    fragment.paragraphY = y;
    fragment.paragraphHeight = paragraphLineBottom - paragraphLineTop;
    const localLines = wholeBlock ? current.lines : fragment.paragraph.getLineMetrics();
    const topInkBleedPx = localLines.length > 0 ? ReaderV2Paginator.lineTopInkGuard(localLines[0]) : 1;
    const bottomInkBleedPx = localLines.length > 0 ?
      ReaderV2Paginator.lineBottomInkGuard(localLines[localLines.length - 1]) : 1;
    fragment.clipRect = new ReaderV2Rect(x, y - topInkBleedPx, x + width,
      y + paragraphLineBottom - paragraphLineTop + bottomInkBleedPx);
    fragment.localStart = first.startIndex;
    fragment.localEnd = last.endIndex;
    fragment.displayStart = current.block.displayStart + fragment.localStart;
    fragment.displayEnd = current.block.displayStart + fragment.localEnd;
    ReaderV2Paginator.appendRegexDecorations(fragment, regexStyles);
    return fragment;
  }

  private static appendRegexDecorations(fragment: ReaderV2PageFragment,
    regexStyles: ReaderV2SpanStyleRange[]): void {
    if (!fragment.paragraph) return;
    for (const style of regexStyles) {
      if (!style.decorationEnabled || !style.decorationStyleId || style.decorationSizePx <= 0 ||
        style.end <= fragment.displayStart || style.start >= fragment.displayEnd) continue;
      const localStart = Math.max(0, style.start - fragment.displayStart);
      const localEnd = Math.min(fragment.localEnd - fragment.localStart, style.end - fragment.displayStart);
      if (localEnd <= localStart) continue;
      const fragmentText = fragment.selectionRuns.map((run: ReaderV2SelectionRun): string => run.text).join('');
      const lines = fragment.paragraph.getLineMetrics();
      for (const line of lines) {
        const segmentStart = Math.max(localStart, line.startIndex);
        const segmentEnd = Math.min(localEnd, line.endIndex);
        if (segmentEnd <= segmentStart) continue;
        const boxes = fragment.paragraph.getRectsForRange({ start: segmentStart, end: segmentEnd },
          graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
        if (boxes.length === 0) continue;
        // A single logical regex run can be split into several native glyph runs when it contains
        // punctuation, emoji or another character that falls back to a different font. Harmony then
        // returns one rect for each glyph run even though all of them are on this same visual line.
        // Using only boxes[0] made the bubble appear to stop at the first special symbol. Merge every
        // rect owned by this line so the decoration follows the complete regex match.
        let boxLeft = boxes[0].rect.left;
        let boxTop = boxes[0].rect.top;
        let boxRight = boxes[0].rect.right;
        let boxBottom = boxes[0].rect.bottom;
        for (let boxIndex = 1; boxIndex < boxes.length; boxIndex++) {
          const nextBox = boxes[boxIndex].rect;
          boxLeft = Math.min(boxLeft, nextBox.left);
          boxTop = Math.min(boxTop, nextBox.top);
          boxRight = Math.max(boxRight, nextBox.right);
          boxBottom = Math.max(boxBottom, nextBox.bottom);
        }
        const segment = new ReaderV2RegexBubbleSegment();
        segment.styleId = style.decorationStyleId;
        segment.text = fragmentText.substring(segmentStart, segmentEnd);
        segment.leading = style.start >= fragment.displayStart && segmentStart === localStart;
        segment.trailing = style.end <= fragment.displayEnd && segmentEnd === localEnd;
        segment.capSizePx = style.decorationSizePx;
        segment.fontSizePx = style.fontSizePx;
        segment.fontFamily = style.fontFamily;
        segment.textColor = style.color;
        segment.backgroundColor = style.backgroundColor;
        segment.radiusTopLeftPx = segment.leading ? style.radiusTopLeftPx : 0;
        segment.radiusBottomLeftPx = segment.leading ? style.radiusBottomLeftPx : 0;
        segment.radiusTopRightPx = segment.trailing ? style.radiusTopRightPx : 0;
        segment.radiusBottomRightPx = segment.trailing ? style.radiusBottomRightPx : 0;
        segment.shadowEnabled = style.shadowEnabled;
        segment.shadowColor = style.shadowColor;
        segment.shadowRadiusPx = style.shadowRadiusPx;
        segment.shadowOffsetXPx = style.shadowOffsetXPx;
        segment.shadowOffsetYPx = style.shadowOffsetYPx;
        const textLeft = fragment.paragraphX + boxLeft;
        const textRight = fragment.paragraphX + boxRight;
        const contentLeft = fragment.paragraphX;
        const contentRight = fragment.clipRect.right;
        // Leading space is reserved on the preceding glyph, while trailing space is part of the decorated run's
        // last glyph advance. Keep both caps inside that measured space and hard-clip them to the text column.
        // This prevents decorations from invading neighbouring text or crossing the user's left/right margins.
        const left = Math.max(contentLeft,
          textLeft - (segment.leading ? style.decorationSizePx : 0));
        const right = Math.min(contentRight, textRight);
        segment.leadingCapWidthPx = segment.leading ?
          Math.max(0, Math.min(style.decorationSizePx, textLeft - left)) : 0;
        segment.trailingCapWidthPx = segment.trailing ?
          Math.max(0, Math.min(style.decorationSizePx, right - left - segment.leadingCapWidthPx)) : 0;
        // RectHeightStyle.TIGHT follows the actual native glyph run. Add a small deterministic cushion for the
        // bubble background and let the caps expand it when necessary. This keeps decoration geometry centred on
        // the already-laid-out text without introducing a second text baseline.
        const glyphTop = fragment.paragraphY + boxTop;
        const glyphBottom = fragment.paragraphY + boxBottom;
        const glyphCenter = (glyphTop + glyphBottom) / 2;
        const verticalPadding = Math.max(1, style.fontSizePx * 0.08);
        const capHalf = style.decorationSizePx / 2;
        const top = Math.min(glyphTop - verticalPadding, glyphCenter - capHalf);
        const bottom = Math.max(glyphBottom + verticalPadding, glyphCenter + capHalf);
        if (right > left) {
          segment.rect = new ReaderV2Rect(left, top, right, bottom);
          fragment.regexBubbleSegments.push(segment);
        }
      }
    }
  }

  private static finalizePageSelection(page: ReaderV2PageLayout): void {
    if (page.fragments.length === 0) return;
    let text = '';
    let first: ReaderV2PageFragment | null = null;
    let last: ReaderV2PageFragment | null = null;
    for (const fragment of page.fragments) {
      if (!fragment.paragraph) {
        // Image fragments own no selectable text: the transparent selection Text only contains prose.
        fragment.selectionPageStart = text.length;
        fragment.selectionPageEnd = text.length;
        continue;
      }
      if (last) {
        text += '\n';
        last.selectionBreakAfter = true;
      }
      fragment.selectionPageStart = text.length;
      for (const run of fragment.selectionRuns) text += run.text;
      fragment.selectionPageEnd = text.length;
      if (!first) first = fragment;
      last = fragment;
    }
    if (!first || !last) return;
    page.selectionText = text;
    page.selectionX = page.contentRect.left;
    page.selectionY = first.paragraphY;
    page.selectionWidth = page.contentRect.width();
    page.selectionHeight = Math.max(1, last.paragraphY + last.paragraphHeight - first.paragraphY);
  }

  private static buildSelectionRuns(document: ReaderV2Document, block: ReaderV2Block,
    snapshot: ReaderV2LayoutSnapshot, regexStyles: ReaderV2SpanStyleRange[], sliceStart: number,
    sliceEnd: number): ReaderV2SelectionRun[] {
    const result: ReaderV2SelectionRun[] = [];
    const safeStart = Math.max(0, Math.min(block.text.length, sliceStart));
    const safeEnd = Math.max(safeStart, Math.min(block.text.length, sliceEnd));
    const boundaries = ReaderV2Paginator.styleBoundaries(document, block, regexStyles, safeStart, safeEnd);
    for (let index = 0; index < boundaries.length - 1; index++) {
      const start = boundaries[index];
      const end = boundaries[index + 1];
      if (end <= start) continue;
      const style = ReaderV2Paginator.styleAt(document, block, block.displayStart + start, snapshot, regexStyles);
      const families = style.fontFamilies;
      result.push(new ReaderV2SelectionRun(block.text.substring(start, end), Number(style.fontSize),
        families && families.length > 0 ? families[0] : '', block.title || block.headingLevel > 0 ? 600 : snapshot.fontWeight,
        Number(style.letterSpacing || 0)));
    }
    return result;
  }

  private static appendActionAreas(page: ReaderV2PageLayout, fragment: ReaderV2PageFragment,
    actions: ReaderV2InlineAction[], snapshot: ReaderV2LayoutSnapshot): void {
    if (!fragment.paragraph) return;
    const firstAction = ReaderV2Paginator.firstActionWhoseEndExceeds(actions, fragment.displayStart);
    for (let index = firstAction; index < actions.length; index++) {
      const action = actions[index];
      if (action.displayStart >= fragment.displayEnd) break;
      if (action.displayEnd <= fragment.displayStart || action.displayStart >= fragment.displayEnd) continue;
      const start = Math.max(0, action.displayStart - fragment.displayStart);
      const end = Math.min(fragment.localEnd - fragment.localStart, action.displayEnd - fragment.displayStart);
      if (end <= start) continue;
      const boxes = fragment.paragraph.getRectsForRange({ start: start, end: end },
        graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.MAX);
      for (const box of boxes) {
        const left = Math.max(fragment.clipRect.left, fragment.paragraphX + box.rect.left);
        const top = Math.max(fragment.clipRect.top, fragment.paragraphY + box.rect.top);
        const right = Math.min(fragment.clipRect.right, fragment.paragraphX + box.rect.right);
        const bottom = Math.min(fragment.clipRect.bottom, fragment.paragraphY + box.rect.bottom);
        if (right <= left || bottom <= top) continue;
        const hit = new ReaderV2ActionHitArea();
        hit.actionId = action.id;
        hit.marker = action.marker;
        hit.rect = new ReaderV2Rect(left, top, right, bottom);
        page.actions.push(hit);
      }
      ReaderV2Paginator.appendCommentBubble(fragment, action, snapshot);
    }
  }

  /**
   * One bubble piece per visual line the label occupies. The height comes from the comment font rather than the
   * glyph boxes so counts, CJK labels and padding spaces all get the same bubble height.
   */
  private static appendCommentBubble(fragment: ReaderV2PageFragment, action: ReaderV2InlineAction,
    snapshot: ReaderV2LayoutSnapshot): void {
    if (!fragment.paragraph) return;
    const localStart = Math.max(0, action.bubbleStart - fragment.displayStart);
    const localEnd = Math.min(fragment.localEnd - fragment.localStart, action.displayEnd - fragment.displayStart);
    if (localEnd <= localStart) return;
    const scale = ReaderCommentBubbleSize.scale(action.label, snapshot.commentBubbleSize);
    const height = ReaderCommentBubblePainter.heightFor(snapshot.commentFontSizePx) * scale;
    const inflateX = snapshot.commentFontSizePx * 0.18 * scale;
    const pieces: ReaderV2CommentBubbleSegment[] = [];
    for (const line of fragment.paragraph.getLineMetrics()) {
      const segmentStart = Math.max(localStart, line.startIndex);
      const segmentEnd = Math.min(localEnd, line.endIndex);
      if (segmentEnd <= segmentStart) continue;
      const boxes = fragment.paragraph.getRectsForRange({ start: segmentStart, end: segmentEnd },
        graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
      let left = Number.POSITIVE_INFINITY;
      let right = Number.NEGATIVE_INFINITY;
      let top = Number.POSITIVE_INFINITY;
      let bottom = Number.NEGATIVE_INFINITY;
      for (const box of boxes) {
        if (box.rect.right <= box.rect.left) continue;
        left = Math.min(left, box.rect.left);
        right = Math.max(right, box.rect.right);
        if (box.rect.bottom > box.rect.top) {
          top = Math.min(top, box.rect.top);
          bottom = Math.max(bottom, box.rect.bottom);
        }
      }
      if (!Number.isFinite(left) || !Number.isFinite(top)) continue;
      const centerY = fragment.paragraphY + (top + bottom) / 2;
      const segment = new ReaderV2CommentBubbleSegment();
      segment.style = snapshot.commentBubble;
      segment.scale = scale;
      segment.tail = false;
      segment.rect = new ReaderV2Rect(fragment.paragraphX + left - inflateX, centerY - height / 2,
        fragment.paragraphX + right + inflateX, centerY + height / 2);
      pieces.push(segment);
    }
    if (pieces.length === 0) return;
    pieces[pieces.length - 1].tail = action.displayEnd <= fragment.displayEnd;
    for (const piece of pieces) fragment.commentBubbleSegments.push(piece);
  }

  private static firstActionWhoseEndExceeds(actions: ReaderV2InlineAction[], offset: number): number {
    let low = 0;
    let high = actions.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (actions[middle].displayEnd <= offset) low = middle + 1;
      else high = middle;
    }
    return low;
  }

  private static lineBottom(line: graphicsText.LineMetrics): number {
    return line.topHeight + line.height;
  }

  private static lineTopInkGuard(line: graphicsText.LineMetrics): number {
    const ascent = Math.abs(line.ascent);
    const inkTop = line.baseline - ascent;
    const overflow = Math.max(0, line.topHeight - inkTop);
    return Math.max(1, Math.ceil(overflow + 0.01));
  }

  private static lineBottomInkGuard(line: graphicsText.LineMetrics): number {
    const descent = Math.abs(line.descent);
    const inkBottom = line.baseline + descent;
    const overflow = Math.max(0, inkBottom - ReaderV2Paginator.lineBottom(line));
    return Math.max(1, Math.ceil(overflow + 0.01));
  }

  private static graphicsColor(value: number): common2D.Color {
    const color = value >>> 0;
    return {
      alpha: (color >>> 24) & 0xFF,
      red: (color >>> 16) & 0xFF,
      green: (color >>> 8) & 0xFF,
      blue: color & 0xFF
    };
  }
}
