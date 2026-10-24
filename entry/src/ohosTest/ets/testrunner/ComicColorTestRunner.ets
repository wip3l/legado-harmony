import { AppAiHost } from '../../../main/ets/utils/AppAiHost';
import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { ComicColorizer } from '@legado/aiengine';
import { ComicColorCodec } from '@legado/aiengine';
import { openComicTestContext } from './ComicTestContext';

/** Device-only smoke test, never included in the release HAP. Uses generated pixels, no user books. */
export default class ComicColorTestRunner implements TestRunner {
  onPrepare(): void { AppAiHost.install(); }

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    try {
      await openComicTestContext();
      await this.verify();
      await delegator.finishTest('PASS ComicColor', 0);
    } catch (error) {
      await delegator.finishTest(`FAIL ComicColor: ${(error as Error).message}`, -1);
    }
  }

  async verify(): Promise<void> {
      // Native JPEG round-trip catches the platform's default BGRA source interpretation.
      const red = new Uint8Array(32 * 32 * 4);
      for (let i = 0; i < red.length; i += 4) {
        red[i] = 220; red[i + 1] = 60; red[i + 2] = 20; red[i + 3] = 255;
      }
      const encoded = await ComicColorCodec.jpeg(red, { width: 32, height: 32 });
      const redSource = image.createImageSource(encoded);
      const redMap = await redSource.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      try {
        const data = new ArrayBuffer(redMap.getPixelBytesNumber());
        await redMap.readPixelsToBuffer(data);
        const rgb = new Uint8Array(data);
        if (Math.abs(rgb[0] - 220) > 5 || Math.abs(rgb[1] - 60) > 5 || Math.abs(rgb[2] - 20) > 5) {
          throw new Error('JPEG red/blue channel order is wrong');
        }
      } finally { await redMap.release(); await redSource.release(); }
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const context = delegator.getAppContext().createModuleContext('entry') as common.Context;
      const width = 1350;
      const height = 1920;
      const pixels = new Uint8Array(width * height * 4);
      for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
          const at = (y * width + x) * 4;
          const border = x < 12 || x >= width - 12 || y < 12 || y >= height - 12;
          const value = border || x % 47 < 3 || y % 71 < 3 ? 0 : Math.round(64 + x / width * 191);
          pixels[at] = value;
          pixels[at + 1] = value;
          pixels[at + 2] = value;
          pixels[at + 3] = 255;
        }
      }
      const map = await image.createPixelMap(pixels.buffer, {
        size: { width: width, height: height }, pixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const packer = image.createImagePacker();
      let bytes: ArrayBuffer;
      try { bytes = await packer.packToData(map, { format: 'image/jpeg', quality: 100 }); }
      finally { await packer.release(); await map.release(); }
      const source = `data:image/jpeg;base64,${new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes))}`;
      let cancelled = false;
      try { await ComicColorizer.colorize(context, source, (): boolean => false, (): void => {}); }
      catch (error) { cancelled = (error as Error).message === ComicColorizer.CANCELLED; }
      if (!cancelled) throw new Error('pre-start cancellation failed');
      let result = await ComicColorizer.colorize(context, source, (): boolean => true,
        (status: string): void => { console.info(`[ComicColorTest] ${status}`); });
      if (result.cached) {
        fs.unlinkSync(new fileUri.FileUri(result.uri).path);
        result = await ComicColorizer.colorize(context, source, (): boolean => true, (): void => {});
      }
      if (!result.uri) throw new Error('missing image output');
      const cached = await ComicColorizer.colorize(context, source, (): boolean => true, (): void => {});
      if (!cached.cached || cached.uri !== result.uri) throw new Error('cache did not hit');
      const local = `${context.cacheDir}/comic-color-test.png`;
      const fixture = fs.openSync(local, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(fixture.fd, bytes); } finally { fs.closeSync(fixture); }
      try {
        const fromFile = await ComicColorizer.colorize(context, local, (): boolean => true, (): void => {});
        if (!fromFile.cached || fromFile.uri !== result.uri) throw new Error('local file differs from data URI');
      } finally { fs.unlinkSync(local); }
      const file = fs.openSync(result.uri, fs.OpenMode.READ_ONLY);
      const decoded = image.createImageSource(file.fd);
      try {
        const info = await decoded.getImageInfo();
        if (info.size.width !== width || info.size.height !== height) throw new Error('output dimensions differ');
        const check = await decoded.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
        try {
          const data = new ArrayBuffer(check.getPixelBytesNumber());
          await check.readPixelsToBuffer(data);
          const rgba = new Uint8Array(data);
          const stride = check.getBytesNumberPerRow();
          for (const y of [4, height - 5]) {
            for (const x of [4, width - 5]) {
              const i = y * stride + x * 4;
              if (rgba[i] > 20 || rgba[i + 1] > 20 || rgba[i + 2] > 20) {
                throw new Error(`image shrank into a white canvas: corner ${x},${y}`);
              }
            }
          }
        } finally { await check.release(); }
      } finally { await decoded.release(); fs.closeSync(file); }
      fs.unlinkSync(new fileUri.FileUri(result.uri).path);
      let active = true;
      let inFlightCancelled = false;
      try {
        await ComicColorizer.colorize(context, source, (): boolean => active,
          (status: string): void => { if (status === '正在本机着色…') active = false; });
      } catch (error) { inFlightCancelled = (error as Error).message === ComicColorizer.CANCELLED; }
      if (!inFlightCancelled) throw new Error('in-flight cancellation failed');
      const recovered = await ComicColorizer.colorize(context, source, (): boolean => true, (): void => {});
      if (!recovered.uri || recovered.cached) throw new Error('cancelled inference published a cache or blocked the queue');
      fs.unlinkSync(new fileUri.FileUri(recovered.uri).path);
      await delegator.print(`[ComicColorTest] PASS total=${result.elapsedMs}ms inference=${result.inferenceMs}ms ` +
        `recovery=${recovered.elapsedMs}ms; cache, local file, cancellation, recovery and JPEG decoding passed\n`);
      const visualPath = `${context.cacheDir}/comic-color-visual-fixture.jpg`;
      if (fs.accessSync(visualPath)) {
        const visual = await ComicColorizer.colorize(context, visualPath, (): boolean => true, (): void => {});
        fs.copyFileSync(new fileUri.FileUri(visual.uri).path, `${context.cacheDir}/comic-color-visual-result.jpg`);
        await delegator.print(`[ComicColorTest] VISUAL total=${visual.elapsedMs}ms inference=${visual.inferenceMs}ms\n`);
      }
  }
}
