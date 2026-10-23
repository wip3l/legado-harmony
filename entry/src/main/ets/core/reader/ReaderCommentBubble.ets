import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import image from '@ohos.multimedia.image';

/**
 * Resolved look of a paragraph-comment / 本章说 bubble: a speech bubble with a tail whose shape, colours and small
 * ornament follow the theme's emphasis-bubble style. Colours are ARGB numbers.
 */
export class ReaderCommentBubbleStyle {
  styleId: string = '';
  cut: boolean = false;
  /** Corner radius as a fraction of the bubble height; 0.5 is a full pill. */
  radiusRatio: number = 0.5;
  /** Absolute corner radius in px set by a source's 段评样式; overrides radiusRatio when >= 0. */
  radiusPx: number = -1;
  fill: number = 0xFF8A9099;
  stroke: number = 0xFF6F757E;
  text: number = 0xFFFFFFFF;
  ornament: string = '';
  ornamentColor: number = 0;
  ornamentAltColor: number = 0;

  identity(): string {
    return `${this.styleId}_${this.cut ? 1 : 0}_${this.radiusRatio}_${Math.round(this.radiusPx * 100) / 100}_` +
      `${this.fill}_${this.stroke}_${this.text}_${this.ornament}_${this.ornamentColor}_${this.ornamentAltColor}`;
  }
}

/** Per-style shape and the light / dark colour sets: [fill, stroke, text, ornament, ornamentAlt]. */
class ReaderCommentBubbleSpec {
  cut: boolean;
  radiusRatio: number;
  ornament: string;
  light: number[];
  dark: number[];

  constructor(cut: boolean, radiusRatio: number, ornament: string, light: number[], dark: number[]) {
    this.cut = cut;
    this.radiusRatio = radiusRatio;
    this.ornament = ornament;
    this.light = light;
    this.dark = dark;
  }
}

// Light pages get a solid bubble with light text and dark pages a pale bubble with dark text, so the comment
// count always reads opposite to the theme's dialogue bubble, which is a soft tint of the page in both modes.
const PLAIN_SPEC: ReaderCommentBubbleSpec = new ReaderCommentBubbleSpec(false, 0.5, '',
  [0xFF8A9099, 0xFF6F757E, 0xFFFFFFFF, 0, 0], [0xFFC9CDD3, 0xFF9AA0A8, 0xFF2A2E33, 0, 0]);

const COMMENT_BUBBLE_SPECS: Map<string, ReaderCommentBubbleSpec> = new Map<string, ReaderCommentBubbleSpec>([
  ['classic-glass', new ReaderCommentBubbleSpec(false, 0.5, 'sparkle',
    [0xFF4B9DE1, 0xFF2F7FC4, 0xFFFFFFFF, 0xFF75BDF2, 0], [0xFFBFE0FF, 0xFF75BDF2, 0xFF163A60, 0xFFEAF7FF, 0])],
  ['warm-scroll', new ReaderCommentBubbleSpec(false, 0.18, 'scroll',
    [0xFFB98546, 0xFF8E6230, 0xFFFFF6E6, 0xFFE8CFA5, 0], [0xFFEBD3AE, 0xFFB98546, 0xFF4A3423, 0xFFD1A267, 0])],
  ['forest-dew', new ReaderCommentBubbleSpec(false, 0.5, 'leaf',
    [0xFF5E9474, 0xFF456F58, 0xFFF2FAF4, 0xFF72A184, 0xFFA8D5BA],
    [0xFFCDE7D5, 0xFF75A887, 0xFF234B35, 0xFF8CC2A0, 0xFFE7F5EC])],
  ['ink-brush', new ReaderCommentBubbleSpec(false, 0.2, 'seal',
    [0xFF4C555D, 0xFF353C42, 0xFFF1F3F4, 0xFFA4514B, 0], [0xFFDADDDF, 0xFF9AA8B5, 0xFF252B30, 0xFFC0625B, 0])],
  ['neon-pulse', new ReaderCommentBubbleSpec(true, 0, 'dot',
    [0xFF263C72, 0xFF5E7BFF, 0xFFE6F8FF, 0xFFFF5AE8, 0], [0xFF141A33, 0xFF00D5FF, 0xFFDDFCFF, 0xFFFF5AE8, 0])],
  ['strawberry-ribbon', new ReaderCommentBubbleSpec(false, 0.5, 'sprig',
    [0xFFE76E77, 0xFFB94C54, 0xFFFFF5EF, 0xFF718F6D, 0], [0xFFF6C9CD, 0xFFE76E77, 0xFF6E2A31, 0xFF8FB08A, 0])],
  ['crimson-stamp', new ReaderCommentBubbleSpec(false, 0.08, 'frame',
    [0xFFA5302A, 0xFF7E211C, 0xFFFFF3EE, 0xFFF3C9C1, 0], [0xFFF3D9D3, 0xFFC74F47, 0xFF74201C, 0xFFC74F47, 0])],
  ['celadon-slip', new ReaderCommentBubbleSpec(false, 0.12, 'cord',
    [0xFF6E9580, 0xFF557A68, 0xFFF4FAF6, 0xFFA96B5C, 0], [0xFFD3E3D8, 0xFF9FBBAA, 0xFF2F4A3D, 0xFFC08573, 0])],
  ['rose-frame', new ReaderCommentBubbleSpec(false, 0.5, 'rose',
    [0xFFB84F5B, 0xFF8E3742, 0xFFFFF1F1, 0xFFE7A7AC, 0xFF71806C],
    [0xFFF5D3D6, 0xFFC77A83, 0xFF6E2A33, 0xFFB84F5B, 0xFF8FA08A])],
  ['moon-halo', new ReaderCommentBubbleSpec(false, 0.5, 'moon',
    [0xFF4F7FB8, 0xFF315777, 0xFFF2F8FF, 0xFFE9C46A, 0], [0xFFD5E6FA, 0xFF8BBEFF, 0xFF233A58, 0xFFF2D27A, 0])],
  ['sword-talisman', new ReaderCommentBubbleSpec(false, 0.06, 'diamond',
    [0xFFF3E6D3, 0xFF9B3B31, 0xFF9B3B31, 0xFF9B3B31, 0xFFF3E6D3],
    [0xFFE9D7C2, 0xFFC0574B, 0xFF6B2A22, 0xFFC0574B, 0xFFE9D7C2])],
  ['qingluan-jade', new ReaderCommentBubbleSpec(false, 0.5, 'pendant',
    [0xFF607F79, 0xFF465F5A, 0xFFF7F3EA, 0xFF9C4F62, 0xFFE9D7C2],
    [0xFFCFE0DB, 0xFF81AAA1, 0xFF2F4642, 0xFFB86078, 0xFFF7F1ED])],
  ['pipi-soft-paw', new ReaderCommentBubbleSpec(false, 0.5, 'paw',
    [0xFFD99086, 0xFFB8705F, 0xFFFFF6EE, 0xFFC46F45, 0xFF2A2624],
    [0xFFF3CDC4, 0xFFD98E7E, 0xFF4B342E, 0xFFD9895F, 0xFF8A6B62])],
  ['mecha-comm', new ReaderCommentBubbleSpec(true, 0, 'signal',
    [0xFF2F6FB3, 0xFF17324F, 0xFFF0F8FF, 0xFFE8731F, 0], [0xFF102238, 0xFF9CC4EC, 0xFFE4F8FC, 0xFFE8731F, 0])],
  ['starwish-ribbon', new ReaderCommentBubbleSpec(false, 0.5, 'star',
    [0xFF6D52A8, 0xFF4A3570, 0xFFFBF6FF, 0xFFE3BE58, 0], [0xFFD9C6F2, 0xFF6D52A8, 0xFF4A3570, 0xFFE3BE58, 0])],
  ['gilded-orbit', new ReaderCommentBubbleSpec(false, 0.12, 'folio',
    [0xFF292620, 0xFFC5A36A, 0xFFF2DEAE, 0xFFC5A36A, 0xFF292620],
    [0xFFDEC79A, 0xFFAF925E, 0xFF30291E, 0xFFAF925E, 0xFFF7E8C5])],
  ['harbor-postcard', new ReaderCommentBubbleSpec(false, 0.12, 'postcard',
    [0xFF994057, 0xFF76364C, 0xFFFFF3E9, 0xFF83BDB9, 0xFFFAF3E9],
    [0xFFE9B4A2, 0xFFB77B7E, 0xFF38283B, 0xFF387C7A, 0xFFFAF3E9])],
  ['pencil-mark', new ReaderCommentBubbleSpec(false, 0.15, 'sketch',
    [0xFF2F5D48, 0xFF1F3F31, 0xFFFFF3CF, 0x992F5D48, 0], [0xFFF1DE8A, 0xFF7A6A2E, 0xFF2B2620, 0x99F1DE8A, 0])]
]);

export class ReaderCommentBubbleStyles {
  /** Styles without their own bubble (the plain default theme and the generic emphasis styles) share PLAIN_SPEC. */
  static resolve(styleId: string, dark: boolean): ReaderCommentBubbleStyle {
    const id = (styleId || '').trim().toLowerCase();
    const spec = COMMENT_BUBBLE_SPECS.get(id) ?? PLAIN_SPEC;
    const colors = dark ? spec.dark : spec.light;
    const style = new ReaderCommentBubbleStyle();
    style.styleId = id;
    style.cut = spec.cut;
    style.radiusRatio = spec.radiusRatio;
    style.fill = colors[0];
    style.stroke = colors[1];
    style.text = colors[2];
    style.ornament = spec.ornament;
    style.ornamentColor = colors[3];
    style.ornamentAltColor = colors[4];
    return style;
  }
}

/** A bubble with its label baked in, for previews that can only show an image inline. Sizes are px. */
export class ReaderCommentBubbleImage {
  pixelMap: image.PixelMap;
  width: number;
  height: number;

  constructor(pixelMap: image.PixelMap, width: number, height: number) {
    this.pixelMap = pixelMap;
    this.width = width;
    this.height = height;
  }
}

export class ReaderCommentBubblePainter {
  /** Height of a bubble around a label of this font size. */
  static heightFor(fontSizePx: number): number {
    return fontSizePx * 1.32;
  }

  /** Room ornaments and the tail may use outside the bubble rect, as a fraction of its height. */
  static readonly OVERHANG_RATIO: number = 0.38;

  /** Paints the bubble body, tail and ornament; the label itself is drawn by the caller on top. */
  static paint(canvas: drawing.Canvas, left: number, top: number, right: number, bottom: number,
    style: ReaderCommentBubbleStyle, tail: boolean): void {
    const w = right - left;
    const h = bottom - top;
    if (w <= 0 || h <= 0) return;
    const body = ReaderCommentBubblePainter.bodyPath(left, top, right, bottom, style, tail);

    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderCommentBubblePainter.color(style.fill));
    canvas.attachBrush(brush);
    canvas.drawPath(body);
    canvas.detachBrush();

    if (((style.stroke >>> 24) & 0xFF) > 0) {
      const pen = ReaderCommentBubblePainter.pen(style.stroke,
        Math.max(1, h * (style.ornament === 'folio' ? 0.045 : 0.07)));
      canvas.attachPen(pen);
      canvas.drawPath(body);
      canvas.detachPen();
    }
    ReaderCommentBubblePainter.paintOrnament(canvas, left, top, right, bottom, body, style);
  }

  /** Renders the bubble and its label into a transparent bitmap with room for the ornament and tail. */
  static renderLabel(style: ReaderCommentBubbleStyle, label: string, fontSizePx: number): ReaderCommentBubbleImage | null {
    try {
      const textStyle: graphicsText.TextStyle = {
        fontSize: fontSizePx,
        fontWeight: graphicsText.FontWeight.W500,
        color: ReaderCommentBubblePainter.color(style.text),
        locale: 'zh-Hans'
      };
      const builder = new graphicsText.ParagraphBuilder({ textStyle: textStyle },
        graphicsText.FontCollection.getGlobalInstance());
      builder.pushStyle(textStyle);
      builder.addText(label);
      builder.popStyle();
      const paragraph = builder.build();
      paragraph.layoutSync(fontSizePx * 40);
      const textWidth = Math.ceil(paragraph.getLongestLine());
      const textHeight = paragraph.getHeight();
      const h = ReaderCommentBubblePainter.heightFor(fontSizePx);
      const padX = fontSizePx * 0.42;
      const w = Math.max(h, textWidth + padX * 2);
      const margin = Math.ceil(h * ReaderCommentBubblePainter.OVERHANG_RATIO);
      const width = Math.ceil(w + margin * 2);
      const height = Math.ceil(h + margin * 2);
      const options: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.PREMUL,
        editable: true
      };
      const pixelMap = image.createPixelMapSync(new ArrayBuffer(width * height * 4), options);
      const canvas = new drawing.Canvas(pixelMap);
      ReaderCommentBubblePainter.paint(canvas, margin, margin, margin + w, margin + h, style, true);
      paragraph.paint(canvas, margin + (w - textWidth) / 2, margin + (h - textHeight) / 2);
      return new ReaderCommentBubbleImage(pixelMap, width, height);
    } catch (error) {
      console.warn(`段评气泡预览绘制失败：${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  private static bodyPath(left: number, top: number, right: number, bottom: number,
    style: ReaderCommentBubbleStyle, tail: boolean): drawing.Path {
    const w = right - left;
    const h = bottom - top;
    const body = new drawing.Path();
    if (style.ornament === 'folio' && style.radiusPx < 0) {
      // A folded ex-libris label. Preserve a source's explicit corner-radius choice.
      const c = Math.min(h * 0.20, w / 4);
      const r = h * 0.10;
      body.moveTo(left + r, top);
      body.lineTo(right - c, top);
      body.lineTo(right, top + c);
      body.lineTo(right, bottom - r);
      body.quadTo(right, bottom, right - r, bottom);
      body.lineTo(left + c, bottom);
      body.lineTo(left, bottom - c);
      body.lineTo(left, top + r);
      body.quadTo(left, top, left + r, top);
      body.close();
    } else if (style.cut) {
      const c = Math.min(h * 0.26, w / 3);
      body.moveTo(left + c, top);
      body.lineTo(right - c, top);
      body.lineTo(right, top + c);
      body.lineTo(right, bottom - c);
      body.lineTo(right - c, bottom);
      body.lineTo(left + c, bottom);
      body.lineTo(left, bottom - c);
      body.lineTo(left, top + c);
      body.close();
    } else {
      const wanted = style.radiusPx >= 0 ? style.radiusPx : h * style.radiusRatio;
      const r = Math.max(0, Math.min(wanted, h / 2, w / 2));
      body.addRoundRect(new drawing.RoundRect({ left: left, top: top, right: right, bottom: bottom }, r, r));
    }
    if (tail) {
      // The tail's base sits inside the body and the two are merged, so the outline runs around both as one shape.
      const baseLeft = left + Math.min(w * 0.34, h * 0.42);
      const tailPath = new drawing.Path();
      tailPath.moveTo(baseLeft, bottom - h * 0.25);
      tailPath.lineTo(baseLeft + h * 0.36, bottom - h * 0.25);
      if (style.ornament === 'folio') {
        // A small notched bookmark tail, within the same measured overhang as other comments.
        tailPath.lineTo(baseLeft + h * 0.30, bottom + h * 0.26);
        tailPath.lineTo(baseLeft + h * 0.12, bottom + h * 0.16);
        tailPath.lineTo(baseLeft - h * 0.06, bottom + h * 0.26);
      } else {
        tailPath.lineTo(baseLeft - h * 0.1, bottom + h * 0.3);
      }
      tailPath.close();
      body.op(tailPath, drawing.PathOp.UNION);
    }
    return body;
  }

  private static paintOrnament(canvas: drawing.Canvas, left: number, top: number, right: number, bottom: number,
    body: drawing.Path, style: ReaderCommentBubbleStyle): void {
    const h = bottom - top;
    const main = style.ornamentColor;
    const alt = style.ornamentAltColor;
    switch (style.ornament) {
      case 'postcard': {
        const envelope = new drawing.Path();
        envelope.moveTo(left + h * 0.02, top - h * 0.08);
        envelope.lineTo(left + h * 0.33, top - h * 0.08);
        envelope.lineTo(left + h * 0.33, top + h * 0.14);
        envelope.lineTo(left + h * 0.02, top + h * 0.14);
        envelope.close();
        ReaderCommentBubblePainter.fillPath(canvas, envelope, main);
        const fold = new drawing.Path();
        fold.moveTo(left + h * 0.03, top - h * 0.06);
        fold.lineTo(left + h * 0.175, top + h * 0.04);
        fold.lineTo(left + h * 0.32, top - h * 0.06);
        canvas.attachPen(ReaderCommentBubblePainter.pen(alt, Math.max(0.8, h * 0.025)));
        canvas.drawPath(fold);
        canvas.detachPen();
        break;
      }
      case 'folio': {
        // The ribbon sits on the outer corner, clear of even a one-digit comment count.
        const ribbon = new drawing.Path();
        ribbon.moveTo(right - h * 0.25, top - h * 0.18);
        ribbon.lineTo(right + h * 0.06, top - h * 0.18);
        ribbon.lineTo(right + h * 0.06, top + h * 0.28);
        ribbon.lineTo(right - h * 0.095, top + h * 0.18);
        ribbon.lineTo(right - h * 0.25, top + h * 0.28);
        ribbon.close();
        ReaderCommentBubblePainter.fillPath(canvas, ribbon, main);
        const pen = ReaderCommentBubblePainter.pen(alt, Math.max(0.7, h * 0.035));
        canvas.attachPen(pen);
        canvas.drawLine(right - h * 0.17, top - h * 0.06, right - h * 0.02, top - h * 0.06);
        canvas.detachPen();
        break;
      }
      case 'star':
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.starPath(right - h * 0.06, top + h * 0.02,
          h * 0.36), main);
        break;
      case 'sparkle':
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.starPath(right - h * 0.06, top + h * 0.04,
          h * 0.3), main);
        break;
      case 'paw':
        ReaderCommentBubblePainter.fillCircle(canvas, left + h * 0.4, top - h * 0.03, h * 0.15, main);
        ReaderCommentBubblePainter.fillCircle(canvas, left + h * 0.72, top - h * 0.15, h * 0.15, main);
        ReaderCommentBubblePainter.fillCircle(canvas, left + h * 1.04, top - h * 0.03, h * 0.15, alt);
        break;
      case 'frame': {
        const inset = h * 0.15;
        const pen = ReaderCommentBubblePainter.pen(main, Math.max(0.8, h * 0.05));
        canvas.attachPen(pen);
        canvas.drawRect({ left: left + inset, top: top + inset, right: right - inset, bottom: bottom - inset });
        canvas.detachPen();
        break;
      }
      case 'seal': {
        const half = h * 0.18;
        const cx = right - h * 0.06;
        const cy = top + h * 0.04;
        ReaderCommentBubblePainter.fillRect(canvas, cx - half, cy - half, cx + half, cy + half, main);
        break;
      }
      case 'dot':
        ReaderCommentBubblePainter.fillCircle(canvas, right - h * 0.13, top + h * 0.13, h * 0.12, main);
        break;
      case 'leaf':
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.leafPath(right - h * 0.36, top + h * 0.12,
          right + h * 0.2, top - h * 0.3, h * 0.17), main);
        ReaderCommentBubblePainter.fillCircle(canvas, right - h * 0.6, top - h * 0.1, h * 0.08, alt);
        break;
      case 'sprig':
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.leafPath(left + h * 0.5, top + h * 0.1,
          left - h * 0.02, top - h * 0.3, h * 0.17), main);
        break;
      case 'scroll':
        ReaderCommentBubblePainter.fillCircle(canvas, left + h * 0.08, top + h * 0.08, h * 0.16, main);
        ReaderCommentBubblePainter.fillCircle(canvas, right - h * 0.08, bottom - h * 0.08, h * 0.16, main);
        break;
      case 'cord': {
        const pen = ReaderCommentBubblePainter.pen(main, Math.max(1, h * 0.09));
        const cy = top + h * 0.5;
        canvas.attachPen(pen);
        canvas.drawLine(left - h * 0.12, cy, left + h * 0.16, cy);
        canvas.drawLine(right - h * 0.16, cy, right + h * 0.12, cy);
        canvas.detachPen();
        break;
      }
      case 'rose':
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.leafPath(left + h * 0.22, top + h * 0.06,
          left + h * 0.62, top - h * 0.24, h * 0.13), alt);
        ReaderCommentBubblePainter.fillCircle(canvas, left + h * 0.14, top + h * 0.06, h * 0.2, main);
        break;
      case 'moon': {
        const r = h * 0.26;
        const cx = right - h * 0.1;
        const cy = top + h * 0.02;
        const moon = new drawing.Path();
        moon.addCircle(cx, cy, r);
        const bite = new drawing.Path();
        bite.addCircle(cx + r * 0.5, cy - r * 0.32, r * 0.86);
        moon.op(bite, drawing.PathOp.DIFFERENCE);
        ReaderCommentBubblePainter.fillPath(canvas, moon, main);
        break;
      }
      case 'diamond':
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.diamondPath(right - h * 0.42, top,
          h * 0.2), main);
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.diamondPath(right - h * 0.42, top,
          h * 0.08), alt);
        break;
      case 'pendant':
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.diamondPath(right - h * 0.3,
          bottom + h * 0.1, h * 0.14), main);
        ReaderCommentBubblePainter.fillPath(canvas, ReaderCommentBubblePainter.diamondPath(right - h * 0.3,
          bottom + h * 0.1, h * 0.06), alt);
        break;
      case 'signal':
        for (let index = 0; index < 3; index++) {
          const barLeft = right - h * 0.62 + index * h * 0.17;
          ReaderCommentBubblePainter.fillRect(canvas, barLeft, top + h * 0.06 - h * (0.12 + index * 0.08),
            barLeft + h * 0.1, top + h * 0.06, main);
        }
        break;
      case 'sketch': {
        const sketch = new drawing.Path(body);
        sketch.offset(h * 0.07, h * 0.06);
        const pen = ReaderCommentBubblePainter.pen(main, Math.max(0.7, h * 0.04));
        canvas.attachPen(pen);
        canvas.drawPath(sketch);
        canvas.detachPen();
        break;
      }
      default:
        break;
    }
  }

  private static starPath(cx: number, cy: number, r: number): drawing.Path {
    const inner = r * 0.3;
    const path = new drawing.Path();
    path.moveTo(cx, cy - r);
    path.lineTo(cx + inner, cy - inner);
    path.lineTo(cx + r, cy);
    path.lineTo(cx + inner, cy + inner);
    path.lineTo(cx, cy + r);
    path.lineTo(cx - inner, cy + inner);
    path.lineTo(cx - r, cy);
    path.lineTo(cx - inner, cy - inner);
    path.close();
    return path;
  }

  private static diamondPath(cx: number, cy: number, half: number): drawing.Path {
    const path = new drawing.Path();
    path.moveTo(cx, cy - half);
    path.lineTo(cx + half, cy);
    path.lineTo(cx, cy + half);
    path.lineTo(cx - half, cy);
    path.close();
    return path;
  }

  /** Two quadratic arcs between base and tip, bulging `width` to each side. */
  private static leafPath(baseX: number, baseY: number, tipX: number, tipY: number, width: number): drawing.Path {
    const dx = tipX - baseX;
    const dy = tipY - baseY;
    const length = Math.max(0.001, Math.sqrt(dx * dx + dy * dy));
    const nx = -dy / length * width;
    const ny = dx / length * width;
    const mx = (baseX + tipX) / 2;
    const my = (baseY + tipY) / 2;
    const path = new drawing.Path();
    path.moveTo(baseX, baseY);
    path.quadTo(mx + nx, my + ny, tipX, tipY);
    path.quadTo(mx - nx, my - ny, baseX, baseY);
    path.close();
    return path;
  }

  private static fillPath(canvas: drawing.Canvas, path: drawing.Path, color: number): void {
    if (((color >>> 24) & 0xFF) === 0) return;
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderCommentBubblePainter.color(color));
    canvas.attachBrush(brush);
    canvas.drawPath(path);
    canvas.detachBrush();
  }

  private static fillCircle(canvas: drawing.Canvas, cx: number, cy: number, r: number, color: number): void {
    const path = new drawing.Path();
    path.addCircle(cx, cy, r);
    ReaderCommentBubblePainter.fillPath(canvas, path, color);
  }

  private static fillRect(canvas: drawing.Canvas, left: number, top: number, right: number, bottom: number,
    color: number): void {
    const path = new drawing.Path();
    path.moveTo(left, top);
    path.lineTo(right, top);
    path.lineTo(right, bottom);
    path.lineTo(left, bottom);
    path.close();
    ReaderCommentBubblePainter.fillPath(canvas, path, color);
  }

  private static pen(color: number, width: number): drawing.Pen {
    const pen = new drawing.Pen();
    pen.setAntiAlias(true);
    pen.setColor(ReaderCommentBubblePainter.color(color));
    pen.setStrokeWidth(width);
    pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
    return pen;
  }

  // Brush/Pen.setColor(number) only exists from API 18; the colour-object overload works on every supported API.
  private static color(value: number): common2D.Color {
    const color = value >>> 0;
    return {
      alpha: (color >>> 24) & 0xFF,
      red: (color >>> 16) & 0xFF,
      green: (color >>> 8) & 0xFF,
      blue: color & 0xFF
    };
  }
}
