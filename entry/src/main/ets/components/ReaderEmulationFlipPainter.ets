import image from '@ohos.multimedia.image';

/**
 * 卷曲起始区域，对应官方示例 EmulationFlipPage 的 DrawPosition。
 */
export enum ReaderEmulationFlipRegion {
  TOP = 0,
  MIDDLE = 1,
  BOTTOM = 2
}

interface FoldPoint {
  x: number;
  y: number;
}

interface FoldGeometry {
  a: FoldPoint;
  b: FoldPoint;
  c: FoldPoint;
  d: FoldPoint;
  e: FoldPoint;
  f: FoldPoint;
  h: FoldPoint;
  j: FoldPoint;
  k: FoldPoint;
  i: FoldPoint;
  leftShadowDistance: number;
  rightShadowDistance: number;
  topCorner: boolean;
  middleCorner: boolean;
}

/**
 * 仿真翻页（页角卷曲）绘制。
 *
 * 几何与明暗算法移植自 HarmonyOS 最佳实践《阅读器翻页》的官方示例
 * （HarmonyOS_Samples/PageFlip: EmulationFlipPage.ets + PageNodeController.ets + Constants.ets，
 * Apache-2.0）。原实现用 NodeContainer + RenderNode + @ohos.graphics.drawing 绘制；这里改用
 * 仓库既有的 Canvas 管线，几何点位、路径、阴影着色与官方保持一致。
 *
 * 与官方示例的差异：
 * 1. 官方由手指的页角坐标驱动，本实现由翻页进度驱动（进度 0 表示纸张平铺，1 表示完全翻出），
 *    起始区域仍按手指落点取上/中/下。
 * 2. 官方只在右侧卷曲；向前翻页时这里对整个画布做一次水平镜像，把折角移到左侧，仅在绘制纸张
 *    正面贴图时再抵消一次镜像，保证正文文字不被镜像。阴影旋转角仍按官方公式在原始坐标系中计算，
 *    这样镜像后不会出现错位的斜向阴影。
 * 3. 左右双页时翻动的是半页纸：先按官方几何把纸角卷起，进度后段让纸张绕书脊做几何位移
 *    （正面横向按 cos 压缩到书脊，背面再从书脊向另一列按 |cos| 展开），不使用淡入淡出。
 */
export class ReaderEmulationFlipPainter {
  // 对应 Constants.SIXTY_PERCENT。
  private readonly cornerRadiusRatio: number = 0.6;
  // 对应 drawPathAHorizontalShadow 中的 maxShadowWidth 与 +70。
  private readonly horizontalShadowMaxWidth: number = 30;
  private readonly horizontalShadowRightExtend: number = 70;
  private readonly finishedProgress: number = 0.995;
  // 页面完全翻出窗口需要页角点越过左边缘约 0.25 个页宽，故进度 1 对应 1.25 倍行程，
  // 使纸张恰好在本次翻页结束前完全离屏，避免提交目标页时出现回跳。
  private readonly travelOvershoot: number = 1.25;
  // 双页：绕书脊的翻转从该进度开始，到进度 1 恰好转满 180°。
  private readonly doublePageSpineStart: number = 0.15;
  // 双页：卷角只轻轻卷起一点，主体运动交给绕书脊的翻转，避免纸面被折角切掉太多、
  // 正文看起来不跟着纸张走。
  private readonly doublePageFoldCap: number = 0.25;
  // 官方样例的绘制坐标是 px，本绘制器使用 vp；阴影的绝对像素常量需要按该比例换算。
  private vpPerPx: number = 1;
  // 对应 initBrushAndPath 中的 pathABrush / pathCBrush 颜色。
  private readonly paperColor: string = 'rgb(255,235,195)';
  private readonly backTintColor: string = 'rgba(186,172,145,0.47)';
  // 官方为 0xff111111；这里降低不透明度，避免在整页/半页折角时出现生硬的黑带。
  private readonly shadowDeepColor: string = 'rgba(17,17,17,0.5)';
  private readonly shadowLightColor: string = 'rgba(17,17,17,0)';
  private readonly shadowBackDeepColor: string = 'rgba(17,17,17,0.53)';

  draw(context: CanvasRenderingContext2D, page: image.PixelMap, backPage: image.PixelMap | null,
    canvasWidth: number, canvasHeight: number, progress: number, direction: number, region: number,
    doublePage: boolean, columnWidth: number, rightOrigin: number, vpPerPx: number): void {
    this.vpPerPx = vpPerPx > 0 ? vpPerPx : 1;
    const width = Math.max(1, canvasWidth);
    const height = Math.max(1, canvasHeight);
    const curl = Math.max(0, Math.min(1, progress));
    context.clearRect(0, 0, width, height);
    context.imageSmoothingEnabled = true;
    if (!page) {
      return;
    }
    if (doublePage) {
      this.drawDoublePage(context, page, backPage, width, height, curl, direction, region,
        Math.max(1, columnWidth), rightOrigin);
      return;
    }
    if (curl <= 0.004 || curl >= this.finishedProgress) {
      // 平铺与翻出到底都不再需要卷曲层：前者直接铺满当前页，后者由底层目标页接管。
      if (curl <= 0.004) {
        context.drawImage(page, 0, 0, width, height);
      }
      return;
    }
    const geometry = this.buildGeometry(width, height, curl, region);
    if (!geometry) {
      context.drawImage(page, 0, 0, width, height);
      return;
    }
    if (this.isFoldOutOfWindow(geometry, height)) {
      return;
    }
    // 向前翻页：整体水平镜像，把右侧折角搬到左侧。镜像变换是自逆的，绘制正文贴图时再应用一次即可抵消。
    const mirrored = direction < 0;
    context.save();
    if (mirrored) {
      context.translate(width, 0);
      context.scale(-1, 1);
    }
    this.drawPathBShadow(context, geometry, width, height);
    this.drawPathC(context, page, geometry, width, height);
    this.drawPathAContent(context, page, geometry, width, height, mirrored);
    context.restore();
  }

  /**
   * 左右双页：翻动的是半页纸。向后翻时右半页绕书脊向左翻，向前翻时整体水平镜像翻动左半页。
   * 官方几何是平面折角，无法表达"纸翻过去落在另一列"，因此进度后段叠加一次绕书脊的几何位移：
   * 正面按 cos 向书脊压缩，转过 90° 后背面页从书脊向另一列按 |cos| 展开；两者在书脊处宽度
   * 同时归零，交接连续，且全程是纯几何变换而非透明度过渡。
   */
  private drawDoublePage(context: CanvasRenderingContext2D, page: image.PixelMap, backPage: image.PixelMap | null,
    width: number, height: number, curl: number, direction: number, region: number, leafWidth: number,
    rightOrigin: number): void {
    const mirrored = direction < 0;
    // 书脊取整个对开页的中心，右半页绕它转到 180° 时正好铺满左列。
    const spineX = width / 2;
    const fraction = this.doublePageSpineFraction(curl);
    const cos = Math.cos(Math.PI * fraction);
    const foldCurl = Math.min(this.doublePageFoldCap, curl * 1.1);
    if (cos > 0.0005) {
      context.save();
      if (mirrored) {
        context.translate(width, 0);
        context.scale(-1, 1);
      }
      // 纸张只能出现在书脊右侧（镜像后为左侧），避免压到相邻页的正文。
      context.beginPath();
      context.rect(spineX, 0, width - spineX, height);
      context.clip();
      // 绕书脊转动：横向按 cos 压缩，书脊是变换不动点。
      context.translate(spineX, 0);
      context.scale(cos, 1);
      context.translate(-spineX, 0);
      context.translate(rightOrigin, 0);
      if (foldCurl <= 0.004) {
        if (mirrored) {
          context.translate(leafWidth, 0);
          context.scale(-1, 1);
        }
        context.drawImage(page, 0, 0, leafWidth, height);
      } else {
        const geometry = this.buildGeometry(leafWidth, height, foldCurl, region);
        if (!geometry) {
          if (mirrored) {
            context.translate(leafWidth, 0);
            context.scale(-1, 1);
          }
          context.drawImage(page, 0, 0, leafWidth, height);
        } else {
          this.drawPathBShadow(context, geometry, leafWidth, height);
          this.drawPathC(context, page, geometry, leafWidth, height);
          this.drawPathAContent(context, page, geometry, leafWidth, height, mirrored);
        }
      }
      context.restore();
    } else if (backPage) {
      // 背面页从书脊向另一列展开：宽度为 |cos| 个列宽。
      // 书脊侧的边从书脊（90°）平滑过渡到落地列的边沿（180°），保证 180° 时与目标列严格对齐。
      const revealed = Math.min(leafWidth, -cos * leafWidth);
      if (revealed > 0.5) {
        const backFraction = Math.max(0, (fraction - 0.5) / 0.5);
        if (direction > 0) {
          const pinRight = spineX + (leafWidth - spineX) * backFraction;
          context.drawImage(backPage, pinRight - revealed, 0, revealed, height);
        } else {
          const pinLeft = spineX + (rightOrigin - spineX) * backFraction;
          context.drawImage(backPage, pinLeft, 0, revealed, height);
        }
      }
    }
  }

  private doublePageSpineFraction(progress: number): number {
    const value = Math.max(0, Math.min(1,
      (progress - this.doublePageSpineStart) / (1 - this.doublePageSpineStart)));
    return value * value * (3 - 2 * value);
  }

  private buildGeometry(width: number, height: number, progress: number, region: number): FoldGeometry | null {
    const radius = this.cornerRadiusRatio * width;
    let ax = (1 - this.travelOvershoot * progress) * (width - 1);
    ax = Math.min(width - 1, ax);
    const f: FoldPoint = { x: width, y: region === ReaderEmulationFlipRegion.TOP ? 0 : height };
    const topCorner = region === ReaderEmulationFlipRegion.TOP;
    const middleCorner = region === ReaderEmulationFlipRegion.MIDDLE;
    let ay = height - 1;
    if (topCorner || region === ReaderEmulationFlipRegion.BOTTOM) {
      // 对应 calcPointAByTouchPoint：把页角限制在半径 0.6W 的圆上。
      const centerX = width - radius;
      const inside = Math.max(0, radius * radius - (ax - centerX) * (ax - centerX));
      const offset = Math.sqrt(inside);
      ay = topCorner ? offset : height - offset;
    }
    ay = Math.max(1, Math.min(height - 1, ay));
    const a: FoldPoint = { x: ax, y: ay };
    const g: FoldPoint = { x: (a.x + f.x) / 2, y: (a.y + f.y) / 2 };
    const denominatorE = f.x - g.x;
    const denominatorH = f.y - g.y;
    if (Math.abs(denominatorE) < 0.0001 || Math.abs(denominatorH) < 0.0001) {
      return null;
    }
    const e: FoldPoint = { x: g.x - (f.y - g.y) * (f.y - g.y) / denominatorE, y: f.y };
    const h: FoldPoint = { x: f.x, y: g.y - (f.x - g.x) * (f.x - g.x) / denominatorH };
    const c: FoldPoint = { x: e.x - (f.x - e.x) / 2, y: f.y };
    const j: FoldPoint = { x: f.x, y: h.y - (f.y - h.y) / 2 };
    const b = this.intersectionPoint(a, e, c, j);
    const k = this.intersectionPoint(a, h, c, j);
    const d: FoldPoint = { x: (c.x + 2 * e.x + b.x) / 4, y: (2 * e.y + c.y + b.y) / 4 };
    const i: FoldPoint = { x: (j.x + 2 * h.x + k.x) / 4, y: (2 * h.y + j.y + k.y) / 4 };
    // H/J 等控制点在纸张快翻出时会远离窗口，钳制到窗口外的有限范围，避免生成超大路径。
    this.clampPoint(b, width, height);
    this.clampPoint(h, width, height);
    this.clampPoint(j, width, height);
    this.clampPoint(k, width, height);
    return {
      a: a,
      b: b,
      c: c,
      d: d,
      e: e,
      f: f,
      h: h,
      j: j,
      k: k,
      i: i,
      leftShadowDistance: this.pointToLineDistance(d, a, e),
      rightShadowDistance: this.pointToLineDistance(i, a, h),
      topCorner: topCorner,
      middleCorner: middleCorner
    };
  }

  private intersectionPoint(lineOneStart: FoldPoint, lineOneEnd: FoldPoint, lineTwoStart: FoldPoint,
    lineTwoEnd: FoldPoint): FoldPoint {
    const x1 = lineOneStart.x;
    const y1 = lineOneStart.y;
    const x2 = lineOneEnd.x;
    const y2 = lineOneEnd.y;
    const x3 = lineTwoStart.x;
    const y3 = lineTwoStart.y;
    const x4 = lineTwoEnd.x;
    const y4 = lineTwoEnd.y;
    const denominatorOne = (x3 - x4) * (y1 - y2) - (x1 - x2) * (y3 - y4);
    const denominatorTwo = (y1 - y2) * (x3 - x4) - (x1 - x2) * (y3 - y4);
    if (Math.abs(denominatorOne) < 0.0001 || Math.abs(denominatorTwo) < 0.0001) {
      return { x: lineOneStart.x, y: lineOneStart.y };
    }
    const x = ((x1 - x2) * (x3 * y4 - x4 * y3) - (x3 - x4) * (x1 * y2 - x2 * y1)) / denominatorOne;
    const y = ((y1 - y2) * (x3 * y4 - x4 * y3) - (x1 * y2 - x2 * y1) * (y3 - y4)) / denominatorTwo;
    return { x: x, y: y };
  }

  private pointToLineDistance(point: FoldPoint, lineStart: FoldPoint, lineEnd: FoldPoint): number {
    const a = lineStart.y - lineEnd.y;
    const b = lineEnd.x - lineStart.x;
    const c = lineStart.x * lineEnd.y - lineEnd.x * lineStart.y;
    const length = Math.hypot(a, b);
    if (length < 0.0001) {
      return 0;
    }
    return Math.abs((a * point.x + b * point.y + c) / length);
  }

  // 对应 checkDrawingAreaInWindow：折线完全移出窗口后停止绘制纸张。
  private isFoldOutOfWindow(geometry: FoldGeometry, height: number): boolean {
    const deltaX = geometry.d.x - geometry.i.x;
    if (Math.abs(deltaX) < 0.0001) {
      return true;
    }
    const slope = (geometry.d.y - geometry.i.y) / deltaX;
    const intercept = geometry.d.y - slope * geometry.d.x;
    if (geometry.topCorner && intercept > height) {
      return true;
    }
    return !geometry.topCorner && intercept < 0;
  }

  private clampPoint(point: FoldPoint, width: number, height: number): void {
    point.x = Math.max(-2 * width, Math.min(3 * width, point.x));
    point.y = Math.max(-2 * height, Math.min(3 * height, point.y));
  }

  private pathA(geometry: FoldGeometry, width: number, height: number): Path2D {
    const path = new Path2D();
    const a = geometry.a;
    const b = geometry.b;
    const c = geometry.c;
    const e = geometry.e;
    const h = geometry.h;
    const j = geometry.j;
    const k = geometry.k;
    if (geometry.topCorner) {
      // drawing.Path 在 reset() 后首个 lineTo 隐含从 (0,0) 起画，因此 pathA 是整页减去折角。
      path.moveTo(0, 0);
      path.lineTo(c.x, c.y);
      path.quadraticCurveTo(e.x, e.y, b.x, b.y);
      path.lineTo(a.x, a.y);
      path.lineTo(k.x, k.y);
      path.quadraticCurveTo(h.x, h.y, j.x, j.y);
      path.lineTo(width, height);
      path.lineTo(0, height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, height);
      path.lineTo(c.x, c.y);
      path.quadraticCurveTo(e.x, e.y, b.x, b.y);
      path.lineTo(a.x, a.y);
      path.lineTo(k.x, k.y);
      path.quadraticCurveTo(h.x, h.y, j.x, j.y);
      path.lineTo(width, 0);
    }
    path.closePath();
    return path;
  }

  private pathC(geometry: FoldGeometry): Path2D {
    const path = new Path2D();
    const a = geometry.a;
    const b = geometry.b;
    const d = geometry.d;
    const i = geometry.i;
    const k = geometry.k;
    path.moveTo(i.x, i.y);
    path.lineTo(d.x, d.y);
    path.lineTo(b.x, b.y);
    path.lineTo(a.x, a.y);
    path.lineTo(k.x, k.y);
    path.closePath();
    return path;
  }

  // 对应 drawPathC：纸张背面区域 + 反射内容 + 背页阴影。
  private drawPathC(context: CanvasRenderingContext2D, page: image.PixelMap, geometry: FoldGeometry,
    width: number, height: number): void {
    const path = this.pathC(geometry);
    context.save();
    context.fillStyle = this.paperColor;
    context.fill(path);

    const e = geometry.e;
    const f = geometry.f;
    const h = geometry.h;
    const foldLength = Math.hypot(f.x - e.x, h.y - f.y);
    if (foldLength > 0.0001) {
      const sin = (f.x - e.x) / foldLength;
      const cos = (h.y - f.y) / foldLength;
      context.save();
      context.clip(path);
      context.translate(e.x, e.y);
      context.transform(-(1 - 2 * sin * sin), 2 * sin * cos, 2 * sin * cos, 1 - 2 * sin * sin, 0, 0);
      context.translate(-e.x, -e.y);
      context.drawImage(page, 0, 0, width, height);
      context.restore();
    }

    context.fillStyle = this.backTintColor;
    context.fill(path);
    context.restore();

    context.save();
    context.clip(path);
    this.drawPathCShadow(context, geometry, width, height);
    context.restore();
  }

  // 对应 drawPathCShadow。
  private drawPathCShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, width: number,
    height: number): void {
    const c = geometry.c;
    const e = geometry.e;
    const f = geometry.f;
    const h = geometry.h;
    const j = geometry.j;
    const top = c.y;
    const bottom = Math.hypot(width, height) + c.y;
    const midCE = (c.x + e.x) / 2;
    const midJH = (j.y + h.y) / 2;
    const controlDistance = Math.min(Math.abs(midCE - e.x), Math.abs(midJH - h.y));
    let left = 0;
    let right = 0;
    if (geometry.topCorner) {
      left = c.x - this.vpPerPx;
      right = c.x + controlDistance;
    } else {
      left = c.x - controlDistance;
      right = c.x + this.vpPerPx;
    }
    const rotateDegrees = this.rotationDegrees(h.y - f.y, e.x - f.x);
    const startX = geometry.topCorner ? right : left;
    const endX = geometry.topCorner ? left : right;
    this.paintRotatedShadow(context, null, left, top, right, bottom, rotateDegrees, c.x, c.y, endX, top, startX,
      top, [this.shadowLightColor, this.shadowBackDeepColor]);
  }

  // 对应 drawPathBShadow：折页投射到下一页上的阴影。
  private drawPathBShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, width: number,
    height: number): void {
    const a = geometry.a;
    const c = geometry.c;
    const e = geometry.e;
    const f = geometry.f;
    const h = geometry.h;
    const aToF = Math.hypot(a.x - f.x, a.y - f.y);
    const top = c.y;
    const bottom = Math.hypot(width, height) + c.y;
    let left = 0;
    let right = 0;
    if (geometry.topCorner) {
      left = c.x;
      right = c.x + aToF / 4;
    } else {
      left = c.x - aToF / 4;
      right = c.x;
    }
    const rotateDegrees = this.rotationDegrees(h.y - f.y, e.x - f.x);
    const startX = geometry.topCorner ? right : left;
    const endX = geometry.topCorner ? left : right;
    this.paintRotatedShadow(context, null, left, top, right, bottom, rotateDegrees, c.x, c.y, endX, top, startX,
      top, [this.shadowDeepColor, this.shadowLightColor]);
  }

  // 对应 drawPathAContent：纸张正面剩余区域 + 页内阴影。
  private drawPathAContent(context: CanvasRenderingContext2D, page: image.PixelMap, geometry: FoldGeometry,
    width: number, height: number, mirrored: boolean): void {
    const path = this.pathA(geometry, width, height);
    context.save();
    context.clip(path);
    // 纸张正面始终按原方向绘制，保证正文不镜像。镜像变换自逆，再应用一次即可抵消。
    if (mirrored) {
      context.translate(width, 0);
      context.scale(-1, 1);
    }
    context.drawImage(page, 0, 0, width, height);
    context.restore();

    if (geometry.middleCorner) {
      this.drawPathAHorizontalShadow(context, geometry, path, width, height);
    } else {
      this.drawPathALeftShadow(context, geometry, path, width, height);
      this.drawPathARightShadow(context, geometry, path, width, height);
    }
  }

  // 对应 drawPathALeftShadow。
  private drawPathALeftShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, pathA: Path2D,
    width: number, height: number): void {
    const a = geometry.a;
    const d = geometry.d;
    const e = geometry.e;
    const top = e.y;
    const bottom = e.y + height;
    let left = 0;
    let right = 0;
    if (geometry.topCorner) {
      left = e.x - geometry.leftShadowDistance / 2;
      right = e.x;
    } else {
      left = e.x;
      right = e.x + geometry.leftShadowDistance / 2;
    }
    const rotateDegrees = this.rotationDegrees(a.y - e.y, e.x - a.x);
    const startX = geometry.topCorner ? right : left;
    const endX = geometry.topCorner ? left : right;
    const clip = new Path2D();
    const clipHalf = Math.max(geometry.rightShadowDistance, geometry.leftShadowDistance) / 2;
    clip.moveTo(a.x - clipHalf, a.y);
    clip.lineTo(d.x, d.y);
    clip.lineTo(e.x, e.y);
    clip.lineTo(a.x, a.y);
    clip.closePath();
    this.paintRotatedShadow(context, pathA, left, top, right, bottom, rotateDegrees, e.x, e.y, endX, top, startX,
      top, [this.shadowLightColor, this.shadowBackDeepColor], clip);
  }

  // 对应 drawPathARightShadow。
  private drawPathARightShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, pathA: Path2D,
    width: number, height: number): void {
    const a = geometry.a;
    const h = geometry.h;
    const diagonal = Math.hypot(width, height);
    const left = h.x;
    const right = h.x + diagonal * 10;
    let top = 0;
    let bottom = 0;
    if (geometry.topCorner) {
      top = h.y - geometry.rightShadowDistance / 2;
      bottom = h.y;
    } else {
      top = h.y;
      bottom = h.y + geometry.rightShadowDistance / 2;
    }
    const rotateDegrees = this.rotationDegrees(a.x - h.x, a.y - h.y);
    const startTop = geometry.topCorner ? top : bottom;
    const endTop = geometry.topCorner ? bottom : top;
    const clip = new Path2D();
    const clipHalf = Math.max(geometry.rightShadowDistance, geometry.leftShadowDistance) / 2;
    clip.moveTo(a.x - clipHalf, a.y);
    clip.lineTo(h.x, h.y);
    clip.lineTo(a.x, a.y);
    clip.closePath();
    this.paintRotatedShadow(context, pathA, left, top, right, bottom, rotateDegrees, h.x, h.y, left, endTop, left,
      startTop, [this.shadowDeepColor, this.shadowLightColor, this.shadowLightColor, this.shadowLightColor], clip);
  }

  // 对应 drawPathAHorizontalShadow。
  private drawPathAHorizontalShadow(context: CanvasRenderingContext2D, geometry: FoldGeometry, pathA: Path2D,
    width: number, height: number): void {
    const a = geometry.a;
    const left = a.x - Math.min(this.horizontalShadowMaxWidth * this.vpPerPx,
      geometry.rightShadowDistance / 2);
    const right = a.x + this.horizontalShadowRightExtend * this.vpPerPx;
    this.paintRotatedShadow(context, pathA, left, 0, right, height, 0, 0, 0, left, 0, right, 0,
      [this.shadowLightColor, this.shadowBackDeepColor]);
  }

  private rotationDegrees(deltaX: number, deltaY: number): number {
    if (Math.abs(deltaX) < 0.0001 && Math.abs(deltaY) < 0.0001) {
      return 0;
    }
    return Math.atan2(deltaY, deltaX) * 180 / Math.PI;
  }

  /**
   * 在可选裁剪区域内，围绕 (centerX, centerY) 旋转后填充一段线性渐变矩形。
   * gradientStart → gradientEnd 的用法与官方 createLinearGradient(endPt, startPt, colors) 对应。
   */
  private paintRotatedShadow(context: CanvasRenderingContext2D, clipPath: Path2D | null, left: number, top: number,
    right: number, bottom: number, rotateDegrees: number, centerX: number, centerY: number, gradientStartX: number,
    gradientStartY: number, gradientEndX: number, gradientEndY: number, colors: string[],
    intersectPath: Path2D | null = null): void {
    context.save();
    if (clipPath) {
      context.clip(clipPath);
    }
    if (intersectPath) {
      context.clip(intersectPath);
    }
    if (Math.abs(rotateDegrees) > 0.0001) {
      context.translate(centerX, centerY);
      context.rotate(rotateDegrees * Math.PI / 180);
      context.translate(-centerX, -centerY);
    }
    const gradient = context.createLinearGradient(gradientStartX, gradientStartY, gradientEndX, gradientEndY);
    for (let index = 0; index < colors.length; index++) {
      gradient.addColorStop(colors.length <= 1 ? 0 : index / (colors.length - 1), colors[index]);
    }
    context.fillStyle = gradient;
    context.fillRect(left, top, Math.max(1, right - left), Math.max(1, bottom - top));
    context.restore();
  }
}
