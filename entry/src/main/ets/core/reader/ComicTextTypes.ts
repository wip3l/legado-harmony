/** OCR 坐标基于输入原图；不依赖屏幕尺寸，也不伪造系统未返回的置信度。 */
export class ComicTextPoint {
  x: number = 0;
  y: number = 0;
}

export class ComicTextRegion {
  id: string = '';
  /** 同一文字块（通常是一个气泡）的行共用，用于跨行做词组转换。 */
  group: string = '';
  text: string = '';
  points: ComicTextPoint[] = [];
  /** 文字周围的纯色底色 #RRGGBB；底色不纯（网点、画面）时为空串，不覆盖原图。 */
  background: string = '';
  /** 原字颜色 #RRGGBB，重写时沿用。 */
  foreground: string = '';
}

export class ComicTextResult {
  version: number = 4;
  /** 缓存键：内容来源（本地路径＋大小＋修改时间，或网络地址）的摘要。 */
  imageHash: string = '';
  engineVersion: string = '';
  width: number = 0;
  height: number = 0;
  regions: ComicTextRegion[] = [];
  elapsedMs: number = 0;
  tileCount: number = 0;
  supportedLanguages: string[] = [];
}

export class ComicTextTile {
  y: number = 0;
  height: number = 0;
  outputWidth: number = 0;
  outputHeight: number = 0;
  ownerTop: number = 0;
  ownerBottom: number = 0;
}

/** 纯计算部分单独测试；重叠区按原图中的行中心归属，避免条漫重复识别同一句。 */
export class ComicTextGeometry {
  static tiles(width: number, height: number): ComicTextTile[] {
    if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width < 32 || height < 32 ||
      width * height > 80 * 1024 * 1024) {
      throw new Error('图片尺寸不适合识别，请使用较小的漫画图片');
    }
    const scale = Math.min(1, 1536 / width);
    const core = Math.floor(1280 / scale);
    const pad = Math.floor(128 / scale);
    const count = Math.ceil(height / core);
    if (count > 64) throw new Error('图片过长，请分段后识别');
    const tiles: ComicTextTile[] = [];
    for (let top = 0; top < height; top += core) {
      const tile = new ComicTextTile();
      tile.ownerTop = top;
      tile.ownerBottom = Math.min(height, top + core);
      tile.y = Math.max(0, top - pad);
      tile.height = Math.min(height, top + core + pad) - tile.y;
      tile.outputWidth = Math.max(32, Math.round(width * scale));
      tile.outputHeight = Math.max(32, Math.round(tile.height * scale));
      tiles.push(tile);
    }
    return tiles;
  }

  static mapLine(id: string, text: string, points: ComicTextPoint[], tile: ComicTextTile,
    width: number, decodedWidth: number, decodedHeight: number): ComicTextRegion | null {
    if (!text.trim() || points.length !== 4 || decodedWidth <= 0 || decodedHeight <= 0) return null;
    const region = new ComicTextRegion();
    region.id = id;
    region.text = text;
    let centerY = 0;
    for (const point of points) {
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return null;
      const mapped = new ComicTextPoint();
      mapped.x = Math.max(0, Math.min(width, point.x * width / decodedWidth));
      mapped.y = tile.y + Math.max(0, Math.min(tile.height, point.y * tile.height / decodedHeight));
      centerY += mapped.y / points.length;
      region.points.push(mapped);
    }
    if (centerY < tile.ownerTop || centerY >= tile.ownerBottom) return null;
    return region;
  }

  static text(result: ComicTextResult): string {
    return result.regions.map((region: ComicTextRegion): string => region.text).join('\n');
  }
}

export class ComicTextColors {
  background: string = '';
  foreground: string = '';
}

/**
 * 从 OCR 输入切片的像素判断一行字的底色和字色。
 * 外框一圈基本同色、框内除了字只剩底色，才算可以安全覆盖的纯色气泡；网点、渐变、画面一律判为不纯。
 */
export class ComicTextColorSampler {
  /** 与底色每个通道相差不超过此值视为底色（容纳 JPEG 噪点）。 */
  private static readonly NEAR: number = 28;
  /** 与底色相差超过此值视为字。 */
  private static readonly INK: number = 72;

  /**
   * @param others 同一切片里其他行的框。竖排对白列距很窄，外框一圈会落到相邻列的字上，
   *   这些像素是别的字而不是背景，取样时跳过。
   * @param fallback 外圈判断不了时改用的底色（相邻行判出的 #RRGGBB），空串表示没有。
   */
  static sample(pixels: Uint8Array, width: number, height: number, stride: number, bgra: boolean,
    points: ComicTextPoint[], others: ComicTextPoint[][] = [], fallback: string = ''): ComicTextColors {
    const colors = new ComicTextColors();
    if (points.length !== 4 || width <= 0 || height <= 0 || stride < width * 4 ||
      pixels.length < stride * height) {
      return colors;
    }
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const point of points) {
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return colors;
      minX = Math.min(minX, point.x);
      maxX = Math.max(maxX, point.x);
      minY = Math.min(minY, point.y);
      maxY = Math.max(maxY, point.y);
    }
    const thickness = Math.min(maxX - minX, maxY - minY);
    if (thickness < 4) return colors;
    const margin = Math.max(2, Math.round(thickness * 0.25));
    const left = Math.max(0, Math.floor(minX) - margin);
    const top = Math.max(0, Math.floor(minY) - margin);
    const right = Math.min(width - 1, Math.ceil(maxX) + margin);
    const bottom = Math.min(height - 1, Math.ceil(maxY) + margin);
    if (right - left < 4 || bottom - top < 4) return colors;

    const read = (x: number, y: number, out: number[]): void => {
      const offset = y * stride + x * 4;
      out.push(bgra ? pixels[offset + 2] : pixels[offset], pixels[offset + 1],
        bgra ? pixels[offset] : pixels[offset + 2]);
    };
    // 其他行的框（外扩一点盖住字形边缘），只保留和本行外圈相交的。
    const obstacles: number[] = [];
    for (const other of others) {
      if (other === points || other.length !== 4) continue;
      let ol = Infinity;
      let ot = Infinity;
      let or = -Infinity;
      let ob = -Infinity;
      for (const point of other) {
        ol = Math.min(ol, point.x);
        or = Math.max(or, point.x);
        ot = Math.min(ot, point.y);
        ob = Math.max(ob, point.y);
      }
      const grow = Math.max(2, Math.round(Math.min(or - ol, ob - ot) * 0.12));
      if (!Number.isFinite(ol + ot + or + ob) || or + grow < left || ol - grow > right ||
        ob + grow < top || ot - grow > bottom) {
        continue;
      }
      obstacles.push(ol - grow, ot - grow, or + grow, ob + grow);
    }
    const readRing = (x: number, y: number, out: number[]): void => {
      for (let index = 0; index < obstacles.length; index += 4) {
        if (x >= obstacles[index] && x <= obstacles[index + 2] && y >= obstacles[index + 1] &&
          y <= obstacles[index + 3]) {
          return;
        }
      }
      read(x, y, out);
    };
    // 外框一圈：取扩展框边线及向内半个边距处的两圈。
    const ring: number[] = [];
    const inset = Math.max(1, Math.floor(margin / 2));
    for (const offset of [0, inset]) {
      const l = left + offset;
      const t = top + offset;
      const r = right - offset;
      const b = bottom - offset;
      if (r <= l || b <= t) continue;
      const step = Math.max(1, Math.floor(((r - l) + (b - t)) * 2 / 200));
      for (let x = l; x <= r; x += step) {
        readRing(x, t, ring);
        readRing(x, b, ring);
      }
      for (let y = t + step; y < b; y += step) {
        readRing(l, y, ring);
        readRing(r, y, ring);
      }
    }
    const ringCount = ring.length / 3;
    let background: number[] = [];
    if (ringCount >= 12) {
      const median = [0, 1, 2].map((channel: number): number => ComicTextColorSampler.median(ring, channel));
      let near = 0;
      for (let index = 0; index < ring.length; index += 3) {
        if (ComicTextColorSampler.distance(ring, index, median) <= ComicTextColorSampler.NEAR) near++;
      }
      if (near >= ringCount * 0.9) background = median;
    }
    // 外圈碰到气泡边线（贴边的列、气泡上下收窄处）时借用相邻行的底色，只靠框内检查把关。
    if (!background.length) background = ComicTextColorSampler.parseHex(fallback);
    if (!background.length) return colors;

    // 框内：字以外的像素应接近底色；介于两者之间的过多说明字压在网点或画面上。
    const inside: number[] = [];
    const ink: number[] = [];
    const insideStep = Math.max(1, Math.floor(Math.sqrt((maxX - minX) * (maxY - minY) / 2500)));
    for (let y = Math.max(0, Math.floor(minY)); y <= Math.min(height - 1, Math.ceil(maxY)); y += insideStep) {
      for (let x = Math.max(0, Math.floor(minX)); x <= Math.min(width - 1, Math.ceil(maxX)); x += insideStep) {
        read(x, y, inside);
      }
    }
    const insideCount = inside.length / 3;
    if (insideCount < 4) return colors;
    let middle = 0;
    let plain = 0;
    for (let index = 0; index < inside.length; index += 3) {
      const diff = ComicTextColorSampler.distance(inside, index, background);
      if (diff > ComicTextColorSampler.INK) {
        ink.push(inside[index], inside[index + 1], inside[index + 2]);
      } else if (diff > ComicTextColorSampler.NEAR) {
        middle++;
      } else {
        plain++;
      }
    }
    const inkCount = ink.length / 3;
    // 笔画只占字框的一部分，框内底色太少说明字压在色块上；
    // 抗锯齿边缘会产生一些中间色，数量远多于字本身时判为复杂背景。
    if (inkCount === 0 || plain < insideCount * 0.35 ||
      middle > Math.max(insideCount * 0.3, inkCount * 1.5)) {
      return colors;
    }
    colors.background = ComicTextColorSampler.hex(background);
    colors.foreground = ComicTextColorSampler.hex([0, 1, 2].map((channel: number): number =>
      ComicTextColorSampler.median(ink, channel)));
    return colors;
  }

  /**
   * 给底色判不出的行找可借用的底色：取已判出底色、且与它间隔不超过两者中较小字宽 1.5 倍的最近一行。
   * 同一气泡里的相邻行、相邻列都在这个距离内；隔开的气泡通常更远，即便借错也还要过框内检查。
   */
  static neighborBackground(index: number, lines: ComicTextPoint[][], backgrounds: string[]): string {
    const box = ComicTextColorSampler.bounds(lines[index]);
    if (!box.length) return '';
    let best = '';
    let bestGap = Infinity;
    for (let other = 0; other < lines.length; other++) {
      if (other === index || !backgrounds[other]) continue;
      const near = ComicTextColorSampler.bounds(lines[other]);
      if (!near.length) continue;
      const gapX = Math.max(0, near[0] - box[2], box[0] - near[2]);
      const gapY = Math.max(0, near[1] - box[3], box[1] - near[3]);
      const gap = Math.max(gapX, gapY);
      const limit = 1.5 * Math.min(box[2] - box[0], box[3] - box[1], near[2] - near[0], near[3] - near[1]);
      if (gap <= limit && gap < bestGap) {
        best = backgrounds[other];
        bestGap = gap;
      }
    }
    return best;
  }

  /** [左, 上, 右, 下]；点无效时为空数组。 */
  private static bounds(points: ComicTextPoint[]): number[] {
    if (!points || points.length !== 4) return [];
    let left = Infinity;
    let top = Infinity;
    let right = -Infinity;
    let bottom = -Infinity;
    for (const point of points) {
      left = Math.min(left, point.x);
      right = Math.max(right, point.x);
      top = Math.min(top, point.y);
      bottom = Math.max(bottom, point.y);
    }
    return Number.isFinite(left + top + right + bottom) ? [left, top, right, bottom] : [];
  }

  private static parseHex(value: string): number[] {
    const match = /^#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$/.exec(value || '');
    return match ? [parseInt(match[1], 16), parseInt(match[2], 16), parseInt(match[3], 16)] : [];
  }

  private static distance(values: number[], index: number, color: number[]): number {
    return Math.max(Math.abs(values[index] - color[0]), Math.abs(values[index + 1] - color[1]),
      Math.abs(values[index + 2] - color[2]));
  }

  private static median(values: number[], channel: number): number {
    const picked: number[] = [];
    for (let index = channel; index < values.length; index += 3) picked.push(values[index]);
    picked.sort((a: number, b: number): number => a - b);
    return picked[Math.floor(picked.length / 2)];
  }

  private static hex(color: number[]): string {
    return '#' + color.map((value: number): string => Math.round(value).toString(16).padStart(2, '0'))
      .join('').toUpperCase();
  }
}

/** 覆盖在原图上的一块重写文字；坐标、字号都按原图像素，显示时统一乘缩放比。 */
export class ComicTextPatch {
  id: string = '';
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  /** 竖排时每个字之间已插入换行。 */
  text: string = '';
  vertical: boolean = false;
  fontSize: number = 0;
  /** 每行（竖排时为每个字）的高度。 */
  lineHeight: number = 0;
  lines: number = 1;
  color: string = '';
  background: string = '';
}

export class ComicTextLayer {
  imageWidth: number = 0;
  imageHeight: number = 0;
  patches: ComicTextPatch[] = [];
  /** 文字有变化、但底色不纯而没有覆盖的行数。 */
  skipped: number = 0;
  /**
   * 假名字母（平假名、片假名、小写片假名及叠字符号），出现即视为日文行。
   * 不含长音符 ー（U+30FC）和间隔号 ・（U+30FB）：OCR 常把中文竖排的破折号、着重点认成它们。
   */
  private static readonly KANA: RegExp = /[ぁ-ゖゝ-ゟァ-ヺヽ-ヿㇰ-ㇿ]/;

  /**
   * 由识别结果生成文字层：只重写转换后有变化的行。同一文字块先整块转换，长度不变时按原行切回，
   * 让跨行的词组也能匹配；含假名字母的行视为日文，不做繁简转换。
   */
  static build(result: ComicTextResult, convert: (text: string) => string): ComicTextLayer {
    const layer = new ComicTextLayer();
    layer.imageWidth = result.width;
    layer.imageHeight = result.height;
    const groups: Map<string, ComicTextRegion[]> = new Map();
    for (const region of result.regions) {
      const key = region.group || region.id;
      const list = groups.get(key);
      if (list) {
        list.push(region);
      } else {
        groups.set(key, [region]);
      }
    }
    groups.forEach((regions: ComicTextRegion[]): void => {
      const eligible = regions.filter((region: ComicTextRegion): boolean =>
        !ComicTextLayer.KANA.test(region.text));
      const joined = eligible.map((region: ComicTextRegion): string => region.text).join('');
      const whole = joined ? convert(joined) : '';
      let offset = 0;
      for (const region of eligible) {
        let converted = '';
        if (whole.length === joined.length) {
          converted = whole.substring(offset, offset + region.text.length);
          offset += region.text.length;
        } else {
          converted = convert(region.text);
        }
        if (converted === region.text) continue;
        const patch = ComicTextLayer.patch(region, converted, result.width, result.height);
        if (patch) {
          layer.patches.push(patch);
        } else {
          layer.skipped++;
        }
      }
    });
    return layer;
  }

  private static patch(region: ComicTextRegion, text: string, width: number, height: number): ComicTextPatch | null {
    if (!region.background || region.points.length !== 4) return null;
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const point of region.points) {
      minX = Math.min(minX, point.x);
      maxX = Math.max(maxX, point.x);
      minY = Math.min(minY, point.y);
      maxY = Math.max(maxY, point.y);
    }
    const boxWidth = maxX - minX;
    const boxHeight = maxY - minY;
    const chars = Array.from(text.trim());
    if (!chars.length || boxWidth < 4 || boxHeight < 4) return null;
    const patch = new ComicTextPatch();
    patch.id = region.id;
    patch.vertical = chars.length >= 2 && boxHeight > boxWidth * 1.3;
    // 外扩一点盖住字形抗锯齿边缘，但不超出原图。
    const pad = Math.max(1, Math.round(Math.min(boxWidth, boxHeight) * 0.12));
    patch.x = Math.max(0, minX - pad);
    patch.y = Math.max(0, minY - pad);
    patch.width = Math.min(width, maxX + pad) - patch.x;
    patch.height = Math.min(height, maxY + pad) - patch.y;
    if (patch.vertical) {
      const cell = boxHeight / chars.length;
      patch.fontSize = Math.min(boxWidth * 0.9, cell * 0.95);
      patch.lineHeight = cell;
      patch.lines = chars.length;
      patch.text = chars.join('\n');
    } else {
      patch.fontSize = Math.min(boxHeight * 0.86, boxWidth / chars.length * 1.02);
      patch.lineHeight = boxHeight;
      patch.text = chars.join('');
    }
    if (patch.fontSize < 4) return null;
    patch.color = region.foreground || '#000000';
    patch.background = region.background;
    return patch;
  }
}
