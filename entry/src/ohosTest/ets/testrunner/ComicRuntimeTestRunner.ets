import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { MessageEvents } from '@kit.ArkTS';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { window } from '@kit.ArkUI';
import { openComicTestContext } from './ComicTestContext';
import { AppAiHost } from '../../../main/ets/utils/AppAiHost';
import { ComicColorJob, ComicColorMessage } from '@legado/aiengine';

class RuntimeSample {
  name: string = '';
  pass: number = 0;
  totalMs: number = 0;
  predictMs: number = 0;
  backend: string = '';
  device: string = '';
  width: number = 0;
  height: number = 0;
}

/** Repeat the production Worker on explicit fixtures, bypassing result-cache hits only.
 * Never changes account permissions, user books or production calibration records. */
export default class ComicRuntimeTestRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    let testWindow: window.Window | null = null;
    let keptScreenOn = false;
    let result = 'PASS ComicRuntime';
    let code = 0;
    try {
      const context = await openComicTestContext();
      testWindow = await window.getLastWindow(context);
      keptScreenOn = testWindow.getWindowProperties().isKeepScreenOn;
      await testWindow.setWindowKeepScreenOn(true);
      await this.run();
    } catch (error) {
      result = `FAIL ComicRuntime: ${(error as Error).message}`;
      code = -1;
    } finally {
      if (testWindow) await testWindow.setWindowKeepScreenOn(keptScreenOn);
    }
    await delegator.finishTest(result, code);
  }

  private write(path: string, bytes: ArrayBuffer | string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
  }

  private read(path: string): ArrayBuffer {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const bytes = new ArrayBuffer(fs.statSync(file.fd).size);
      let offset = 0;
      while (offset < bytes.byteLength) {
        const part = new ArrayBuffer(bytes.byteLength - offset);
        const count = fs.readSync(file.fd, part, { length: part.byteLength });
        if (count <= 0) throw new Error('Incomplete test fixture');
        new Uint8Array(bytes).set(new Uint8Array(part, 0, count), offset);
        offset += count;
      }
      return bytes;
    } finally { fs.closeSync(file); }
  }

  private async run(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const app = delegator.getAppContext().getApplicationContext();
    const context = app.createModuleContext('entry') as common.Context;
    const dir = app.cacheDir;
    const fixture = `${dir}/comic-color-visual-fixture.jpg`;
    if (!fs.accessSync(fixture)) throw new Error('Explicit visual fixture is required');
    const parameters = abilityDelegatorRegistry.getArguments().parameters;
    const label = parameters['-s runtimeLabel'] || parameters['runtimeLabel'] || 'baseline';
    const mixed = (parameters['-s runtimeMixed'] || parameters['runtimeMixed']) === 'true';
    if (!/^[a-z0-9-]+$/.test(label)) throw new Error('Invalid benchmark label');
    const prefix = `${dir}/comic-runtime`;
    const samples: RuntimeSample[] = [];
    const names = ['portrait', 'landscape', 'square', 'tiny'];
    for (const name of names) {
      const path = `${prefix}-${name}.jpg`;
      if (fs.accessSync(path)) continue;
      if (name === 'portrait') { this.write(path, this.read(fixture)); continue; }
      const source = image.createImageSource(fixture);
      const map = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const packer = image.createImagePacker();
      try {
        if (name === 'landscape') await map.rotate(90);
        else {
          const info = await map.getImageInfo();
          const side = Math.min(info.size.width, info.size.height);
          await map.crop({ x: 0, y: 0, size: { width: side, height: side } });
          const target = name === 'square' ? 512 : 256;
          await map.scale(target / side, target / side);
        }
        this.write(path, await packer.packToData(map, { format: 'image/jpeg', quality: 100 }));
      } finally { await packer.release(); await map.release(); await source.release(); }
    }
    const job = new ComicColorJob();
    for (const model of ['alac', 'alac-npu-portrait', 'alac-npu-landscape']) {
      const data = await context.resourceManager.getRawFileContent(`comic-colorizer/${model}.ms`);
      this.write(`${prefix}-${model}.ms`, data.buffer as ArrayBuffer);
    }
    job.modelPath = `${prefix}-alac.ms`;
    job.npuPortraitPath = `${prefix}-alac-npu-portrait.ms`;
    job.npuLandscapePath = `${prefix}-alac-npu-landscape.ms`;
    const thread = new AppAiHost().createColorWorker();
    try {
      // Return to the first CPU size to exercise resize on a reused dynamic model.
      const sequence = mixed ? ['portrait', 'tiny', 'portrait-return', 'square', 'portrait-final'] : [...names, 'square-return'];
      for (const name of sequence) {
        const fileName = name === 'square-return' ? 'square' : name.startsWith('portrait-') ? 'portrait' : name;
        const passes = mixed ? (name === 'portrait' || name === 'square' ? 2 : 1) : name === 'square-return' ? 1 : 6;
        for (let pass = 0; pass < passes; pass++) {
          job.disableAcceleration = name === 'square' || name === 'tiny' || name === 'square-return';
          job.imageBytes = this.read(`${prefix}-${fileName}.jpg`);
          const started = Date.now();
          const result = await new Promise<ComicColorMessage>((resolve, reject): void => {
            thread.onmessage = (event: MessageEvents): void => {
              const message = event.data as ComicColorMessage;
              if (message.backendProfile) job.backendProfiles.push(message.backendProfile);
              if (message.backendReason) console.info(`[ComicRuntimeBackend] ${message.backendReason}`);
              if (message.error) reject(new Error(message.error));
              else if (message.jpeg?.byteLength > 0) resolve(message);
            };
            thread.onerror = (): void => reject(new Error('Benchmark Worker failed'));
            thread.postMessage(job, [job.imageBytes]);
          });
          const sample = new RuntimeSample();
          sample.name = name; sample.pass = pass; sample.totalMs = Date.now() - started;
          sample.predictMs = result.inferenceMs; sample.backend = result.backend;
          sample.device = result.deviceName; sample.width = result.width; sample.height = result.height;
          samples.push(sample);
          this.write(`${prefix}-${label}.json`, JSON.stringify(samples));
          if (mixed || pass === 1 || name === 'square-return') this.write(`${prefix}-${label}-${name}.jpg`, result.jpeg);
          await delegator.print(`[ComicRuntime] ${label} ${JSON.stringify(sample)}\n`);
          await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 750); });
        }
      }
    } finally { thread.terminate(); }
  }
}
