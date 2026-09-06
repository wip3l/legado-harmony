import graphicsText from '@ohos.graphics.text';
import common2D from '@ohos.graphics.common2D';
import { ReaderV2Block, ReaderV2Document, ReaderV2InlineAction } from './ReaderV2Document';
import { ReaderV2LayoutSnapshot, ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import {
  ReaderV2ActionHitArea,
  ReaderV2PageFragment,
  ReaderV2PageLayout,
  ReaderV2PageSet,
  ReaderV2RegexBubbleSegment,
  ReaderV2SelectionRun
} from './ReaderV2PageLayout';
import { ReaderV2SpanStyleRange } from './ReaderV2Style';

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

  constructor(document: ReaderV2Document, snapshot: ReaderV2LayoutSnapshot,
    regexStyles: ReaderV2SpanStyleRange[]) {
    this.document = document;
    this.snapshot = snapshot;
    this.regexStyles = regexStyles;
    this.pageSet.documentIdentity = document.identity;
    this.pageSet.layoutIdentity = snapshot.identity;
    this.width = snapshot.columnRects.length > 0 ? snapshot.columnRects[0].width() : 0;
    this.pageSet.complete = document.blocks.length === 0 || snapshot.columnRects.length === 0;
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
      let y = column.top;
      let hasContent = false;
      let topInkGuardApplied = false;
      let mustEndPage = false;

      while (session.blockIndex < session.document.blocks.length && !mustEndPage) {
        let current = session.measuredBlock;
        if (!current || current.block !== session.document.blocks[session.blockIndex]) {
          current = ReaderV2Paginator.measureBlock(session.document, session.document.blocks[session.blockIndex],
            session.snapshot, session.regexStyles, session.width);
          session.measuredBlock = current;
        }
        if (current.lines.length === 0) {
          session.blockIndex++;
          session.lineIndex = 0;
          session.measuredBlock = null;
          continue;
        }

        const startsNewBlock = session.lineIndex === 0;
        const spacing = startsNewBlock && hasContent ? session.snapshot.paragraphSpacingPx : 0;
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
        if (hasContent && y + spacing + firstLineHeight > column.bottom + 0.01) {
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
          if (y + relativeBottom > column.bottom + 0.01 && fragmentLastLine >= fragmentFirstLine) break;
          // A single oversized line still owns an otherwise empty page, preventing a pagination dead loop.
          if (y + relativeBottom > column.bottom + 0.01 && hasContent) break;
          fragmentLastLine = session.lineIndex;
          fragmentBottom = ReaderV2Paginator.lineBottom(line);
          session.lineIndex++;
          if (y + relativeBottom >= column.bottom - 0.01) break;
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
          session.snapshot, session.regexStyles, session.width);
        page.fragments.push(fragment);
        ReaderV2Paginator.appendActionAreas(page, fragment, session.document.actions);
        if (!hasContent) page.displayStart = fragment.displayStart;
        page.displayEnd = fragment.displayEnd;
        hasContent = true;
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
      ReaderV2Paginator.finalizePageSelection(page);
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

  private static baseTextStyle(block: ReaderV2Block, snapshot: ReaderV2LayoutSnapshot): graphicsText.TextStyle {
    return {
      fontSize: block.title ? snapshot.titleFontSizePx : snapshot.fontSizePx,
      letterSpacing: snapshot.letterSpacingPx,
      fontFamilies: [block.title ? snapshot.titleFontFamily : snapshot.bodyFontFamily],
      fontWeight: block.title ? graphicsText.FontWeight.W600 : graphicsText.FontWeight.W400,
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
      base.fontSize = snapshot.commentFontSizePx;
      base.color = ReaderV2Paginator.graphicsColor(snapshot.commentTextColor);
      base.backgroundRect = {
        color: ReaderV2Paginator.graphicsColor(snapshot.commentBackgroundColor),
        leftTopRadius: snapshot.commentRadiusPx,
        rightTopRadius: snapshot.commentRadiusPx,
        rightBottomRadius: snapshot.commentRadiusPx,
        leftBottomRadius: snapshot.commentRadiusPx
      };
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
    fragment.paragraph = ReaderV2Paginator.buildParagraph(document, current.block, snapshot, regexStyles, width,
      first.startIndex, last.endIndex);
    fragment.selectionRuns = ReaderV2Paginator.buildSelectionRuns(document, current.block, snapshot, regexStyles,
      first.startIndex, last.endIndex);
    fragment.paragraphX = x;
    fragment.paragraphY = y;
    fragment.paragraphHeight = paragraphLineBottom - paragraphLineTop;
    const localLines = fragment.paragraph.getLineMetrics();
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
    for (let index = 0; index < page.fragments.length; index++) {
      const fragment = page.fragments[index];
      if (index > 0) text += '\n';
      fragment.selectionPageStart = text.length;
      for (const run of fragment.selectionRuns) text += run.text;
      fragment.selectionPageEnd = text.length;
    }
    const first = page.fragments[0];
    const last = page.fragments[page.fragments.length - 1];
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
        families && families.length > 0 ? families[0] : '', block.title, Number(style.letterSpacing || 0)));
    }
    return result;
  }

  private static appendActionAreas(page: ReaderV2PageLayout, fragment: ReaderV2PageFragment,
    actions: ReaderV2InlineAction[]): void {
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
    }
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
