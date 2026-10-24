import { abilityDelegatorRegistry } from '@kit.TestKit';
import { ComicColorComposite, ComicColorPixels } from '@legado/aiengine';

/** Compare every channel with the existing ArkTS formula, including padding, alpha and subarray offsets. */
export async function verifyComicComposite(): Promise<void> {
  const shapes: number[][] = [[137,193,32,48], [193,137,48,32], [71,71,32,32], [64,128,1,32], [128,64,32,1], [32,32,48,48]];
  let maxError = 0;
  let tested = 0;
  for (const shape of shapes) {
    const w = shape[0], h = shape[1], sw = shape[2], sh = shape[3];
    const mw = Math.ceil(sw / 32) * 32, mh = Math.ceil(sh / 32) * 32;
    const stride = w * 4 + 16;
    const pixels = new Uint8Array(stride * h + 8).subarray(8);
    for (let i = 0; i < pixels.length; i++) pixels[i] = (i * 71 + (i % 11) * 13) % 256;
    // Include opaque white / black and low-luminance ink in addition to mixed alpha and RGB.
    pixels.set([0,0,0,255,255,255,255,255,16,16,16,255,32,32,32,255,255,0,0,0]);
    const colors = new Float32Array(mw * mh * 3 + 4).subarray(4);
    const hint = new Float32Array(mw * mh * 5 + 2).subarray(2);
    for (let i = 0; i < colors.length; i++) colors[i] = ((i * 37) % 1001) / 500 - 1;
    for (let i = 0; i < hint.length; i += 5) hint[i] = ((i * 11) % 997) / 996;
    const expected = ComicColorPixels.blend(pixels, w, h, stride, colors, hint, sw, sh, mw, mh);
    const beforeColors = colors.slice();
    const beforePixels = pixels.slice();
    const actual = ComicColorComposite.nativeBlend(pixels, w, h, stride, colors, hint, sw, sh, mw, mh);
    if (actual.length !== expected.length) throw new Error('Native composite length mismatch');
    for (let i = 0; i < actual.length; i++) {
      const delta = Math.abs(actual[i] - expected[i]);
      if (delta > 1) throw new Error(`Native composite mismatch at ${w}x${h}:${i} error=${delta}`);
      maxError = Math.max(maxError, delta);
    }
    for (let i = 0; i < colors.length; i++) if (colors[i] !== beforeColors[i]) throw new Error('Colors mutated');
    for (let i = 0; i < pixels.length; i++) if (pixels[i] !== beforePixels[i]) throw new Error('Source mutated');
    for (let fault = 0; fault < 6; fault++) {
      const invalid = colors.slice();
      if (fault === 0) invalid[0] = NaN;
      if (fault === 1) invalid[0] = 2;
      let rejected = false;
      try {
        ComicColorComposite.nativeBlend(pixels, fault === 2 ? 0 : w, h, fault === 3 ? 1 : stride,
          fault === 4 ? invalid.subarray(3) : invalid, hint, fault === 5 ? mw + 1 : sw, sh, mw, mh);
      } catch (_) { rejected = true; }
      if (!rejected) throw new Error(`Native composite accepted invalid input ${fault}`);
    }
    tested += actual.length;
  }
  await abilityDelegatorRegistry.getAbilityDelegator().print(`[ComicComposite] cases=${shapes.length} channels=${tested} maxError=${maxError}/255; alpha, stride, offsets, borders and invalid buffers passed\n`);
}
