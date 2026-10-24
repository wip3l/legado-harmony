/** Adaptive AlacGAN model contract. Keep in sync with scripts/comic-colorizer/export_model.py. */
export class ComicColorSize {
  width: number = 0;
  height: number = 0;
}

export class ComicColorPixels {
  static readonly VERSION: string = 'alac-fp16-v4';

  static modelSize(width: number, height: number): ComicColorSize {
    ComicColorPixels.fit(width, height, 768);
    const scale = Math.min(1, 768 / Math.max(width, height), 512 / Math.min(width, height));
    return { width: Math.round(width * scale), height: Math.round(height * scale) };
  }

  static padded(size: ComicColorSize): ComicColorSize {
    return { width: Math.max(64, Math.ceil(size.width / 32) * 32),
      height: Math.max(64, Math.ceil(size.height / 32) * 32) };
  }

  static fit(width: number, height: number, side: number): ComicColorSize {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width < 16 || height < 16 ||
      Math.max(width / height, height / width) > 4) {
      throw new Error('本次试验支持普通单页漫画，长条图请先分成单页');
    }
    const scale = Math.min(1, side / Math.max(width, height));
    const size = new ComicColorSize();
    size.width = Math.max(1, Math.round(width * scale));
    size.height = Math.max(1, Math.round(height * scale));
    return size;
  }

  /** AlacGAN NHWC: grayscale [0,1] followed by four zero hint channels. */
  static input(pixels: Uint8Array, width: number, height: number, stride: number,
    modelWidth: number, modelHeight: number): Float32Array {
    if (width < 1 || height < 1 || width > modelWidth || height > modelHeight || stride < width * 4 ||
      pixels.length < stride * height) throw new Error('着色输入尺寸无效');
    const result = new Float32Array(modelWidth * modelHeight * 5);
    for (let i = 0; i < result.length; i += 5) result[i] = 1;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const at = y * stride + x * 4;
        const alpha = pixels[at + 3] / 255;
        const gray = ((pixels[at] * 0.299 + pixels[at + 1] * 0.587 + pixels[at + 2] * 0.114) * alpha +
          255 * (1 - alpha)) / 255;
        const dest = (y * modelWidth + x) * 5;
        result[dest] = gray;
      }
    }
    return result;
  }

  static validateOutput(colors: Float32Array, modelWidth: number, modelHeight: number): void {
    if (colors.length !== modelWidth * modelHeight * 3) {
      throw new Error('着色模型输出尺寸不匹配');
    }
    for (let i = 0; i < colors.length; i++) {
      if (!Number.isFinite(colors[i]) || Math.abs(colors[i]) > 1.01) throw new Error('着色模型输出异常');
    }
  }

  /** The dynamically converted model emits planar NCHW; own and interleave its RGB data. */
  static interleave(planar: Float32Array, width: number, height: number): Float32Array {
    ComicColorPixels.validateOutput(planar, width, height);
    const count = width * height;
    const rgb = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
      rgb[i * 3] = planar[i];
      rgb[i * 3 + 1] = planar[count + i];
      rgb[i * 3 + 2] = planar[count * 2 + i];
    }
    return rgb;
  }

  /** Retain model shading/color (including white skin), restore original high-frequency ink detail. */
  static blend(pixels: Uint8Array, width: number, height: number, stride: number,
    colors: Float32Array, grayHint: Float32Array, smallWidth: number, smallHeight: number,
    modelWidth: number, modelHeight: number): Uint8Array {
    ComicColorPixels.validateOutput(colors, modelWidth, modelHeight);
    if (grayHint.length !== modelWidth * modelHeight * 5) throw new Error('着色输入尺寸无效');
    if (stride < width * 4 || pixels.length < stride * height) throw new Error('原图像素尺寸无效');
    if (smallWidth < 1 || smallHeight < 1 || smallWidth > modelWidth || smallHeight > modelHeight) {
      throw new Error('着色采样尺寸无效');
    }
    // Linear interpolation commutes with RGB - gray. Compute this difference at model resolution,
    // then reuse two horizontally interpolated rows instead of sampling four channels per output pixel.
    const delta = new Float32Array(smallWidth * smallHeight * 3);
    for (let y = 0; y < smallHeight; y++) {
      for (let x = 0; x < smallWidth; x++) {
        const from = y * modelWidth + x;
        const to = (y * smallWidth + x) * 3;
        const gray = grayHint[from * 5] * 255;
        for (let c = 0; c < 3; c++) delta[to + c] = (colors[from * 3 + c] + 1) * 127.5 - gray;
      }
    }
    const columns = new Int32Array(width);
    const fractions = new Float64Array(width);
    for (let x = 0; x < width; x++) {
      const sx = Math.max(0, Math.min(smallWidth - 1, (x + 0.5) * smallWidth / width - 0.5));
      columns[x] = Math.floor(sx);
      fractions[x] = sx - columns[x];
    }
    let top = new Float32Array(width * 3);
    let bottom = new Float32Array(width * 3);
    let topIndex = -1;
    let bottomIndex = -1;
    const fillRow = (row: Float32Array, index: number): void => {
      for (let x = 0; x < width; x++) {
        const x0 = columns[x];
        const left = (index * smallWidth + x0) * 3;
        const right = (index * smallWidth + Math.min(smallWidth - 1, x0 + 1)) * 3;
        const fx = fractions[x];
        for (let c = 0; c < 3; c++) row[x * 3 + c] = delta[left + c] * (1 - fx) + delta[right + c] * fx;
      }
    };
    const result = new Uint8Array(width * height * 4);
    for (let y = 0; y < height; y++) {
      const sy = Math.max(0, Math.min(smallHeight - 1, (y + 0.5) * smallHeight / height - 0.5));
      const y0 = Math.floor(sy);
      const y1 = Math.min(smallHeight - 1, y0 + 1);
      if (topIndex !== y0) {
        if (bottomIndex === y0) {
          const swap = top; top = bottom; bottom = swap;
          bottomIndex = topIndex;
        } else fillRow(top, y0);
        topIndex = y0;
      }
      if (bottomIndex !== y1) { fillRow(bottom, y1); bottomIndex = y1; }
      const fy = sy - y0;
      for (let x = 0; x < width; x++) {
        const at = y * stride + x * 4;
        const alpha = pixels[at + 3] / 255;
        const originalY = (pixels[at] * 0.299 + pixels[at + 1] * 0.587 + pixels[at + 2] * 0.114) * alpha +
          255 * (1 - alpha);
        const dest = (y * width + x) * 4;
        const ink = originalY >= 32 ? 1 : originalY / 32;
        for (let c = 0; c < 3; c++) {
          const difference = top[x * 3 + c] * (1 - fy) + bottom[x * 3 + c] * fy;
          const value = originalY + difference;
          result[dest + c] = ((value < 0 ? 0 : value > 255 ? 255 : value) * ink + 0.5) | 0;
        }
        result[dest + 3] = 255;
      }
    }
    return result;
  }

}
