import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { MessageEvents } from '@kit.ArkTS';
import { AppAiHost } from '../../../main/ets/utils/AppAiHost';
import { ComicColorPixels } from '@legado/aiengine';
import { ComicColorCodec } from '@legado/aiengine';
import { ComicColorInference, ComicColorJob, ComicColorMessage } from '@legado/aiengine';

/** Test-only stage dumps for locating decoder / inference / composite corruption. */
export async function diagnoseComicEdges(): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const context = delegator.getAppContext().createModuleContext('entry') as common.Context;
  // Exercise the raw pixel/model math only. Never modify the production account or entitlement store.
  const prefix = `${context.cacheDir}/comic-edge`;
  if (!fs.accessSync(`${context.cacheDir}/comic-color-visual-fixture.jpg`)) {
    await delegator.print('[ComicEdge] SKIP: optional visual fixture is not installed\n');
    return;
  }
  const write = (suffix: string, bytes: ArrayBuffer): void => {
    const file = fs.openSync(`${prefix}-${suffix}`, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
  };
  const source = image.createImageSource(`${context.cacheDir}/comic-color-visual-fixture.jpg`);
  const full = image.createImageSource(`${context.cacheDir}/comic-color-visual-fixture.jpg`);
  const info = await source.getImageInfo();
  const smallSize = ComicColorPixels.modelSize(info.size.width, info.size.height);
  const size = ComicColorPixels.padded(smallSize);
  if (fs.accessSync(`${prefix}-height.txt`)) size.height = Math.max(size.height, Number(fs.readTextSync(`${prefix}-height.txt`).trim()));
  let precision = 'enforce_fp32';
  let threads = 4;
  let backend = 'auto';
  if (fs.accessSync(`${prefix}-config.txt`)) {
    const config = fs.readTextSync(`${prefix}-config.txt`).trim().split(',');
    size.width = Number(config[0]); size.height = Number(config[1]);
    smallSize.width = Number(config[2]); smallSize.height = Number(config[3]);
    threads = Number(config[4]) || 4; precision = config[5] || precision;
    backend = config[6] || backend;
  }
  const small = await source.createPixelMap({ desiredSize: smallSize, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
  const smallInfo = await small.getImageInfo();
  const bytes = new ArrayBuffer(small.getPixelBytesNumber());
  await small.readPixelsToBuffer(bytes);
  const input = ComicColorPixels.input(new Uint8Array(bytes), smallInfo.size.width, smallInfo.size.height,
    small.getBytesNumberPerRow(), size.width, size.height);
  write('input.bin', input.buffer as ArrayBuffer);
  write('model.ms', (await context.resourceManager.getRawFileContent('comic-colorizer/alac.ms')).buffer as ArrayBuffer);
  const started = Date.now();
  const modelPath = fs.accessSync(`${prefix}-custom.ms`) ? `${prefix}-custom.ms` : `${prefix}-model.ms`;
  if (backend === 'auto' || backend === 'worker') {
    const job = new ComicColorJob();
    job.modelPath = `${prefix}-model.ms`;
    for (const orientation of ['portrait', 'landscape']) {
      write(`${orientation}.ms`, (await context.resourceManager.getRawFileContent(`comic-colorizer/alac-npu-${orientation}.ms`)).buffer as ArrayBuffer);
    }
    job.npuPortraitPath = `${prefix}-portrait.ms`;
    job.npuLandscapePath = `${prefix}-landscape.ms`;
    const report = (message: ComicColorMessage): void => {
      if (message.backendProfile) job.backendProfiles.push(message.backendProfile);
      if (message.accelerationDisabled) job.disableAcceleration = true;
      console.info(`[ComicAcceleration] ${message.backendReason || message.status}`);
    };
    if (backend === 'worker') {
      const thread = new AppAiHost().createColorWorker();
      try {
        for (let pass = 0; pass < 3; pass++) {
          const file = fs.openSync(`${context.cacheDir}/comic-color-visual-fixture.jpg`, fs.OpenMode.READ_ONLY);
          job.imageBytes = new ArrayBuffer(fs.statSync(file.fd).size);
          try { fs.readSync(file.fd, job.imageBytes); } finally { fs.closeSync(file); }
          if (pass === 2) job.disableAcceleration = true;
          const passStart = Date.now();
          const result = await new Promise<ComicColorMessage>((resolve, reject): void => {
            thread.onmessage = (event: MessageEvents): void => {
              const message = event.data as ComicColorMessage;
              report(message);
              if (message.error) reject(new Error(message.error));
              else if (message.jpeg?.byteLength > 0) resolve(message);
            };
            thread.onerror = (): void => reject(new Error('worker failed'));
            thread.postMessage(job, [job.imageBytes]);
          });
          write(`worker-${pass}.jpg`, result.jpeg);
          await delegator.print(`[ComicAcceleration] worker pass=${pass} backend=${result.backend} device=${result.deviceName} inference=${result.inferenceMs}ms total=${Date.now()-passStart}ms output=${result.width}x${result.height}\n`);
          if (result.backend !== (pass === 2 ? 'cpu' : 'nnrt')) throw new Error('Unexpected selected backend');
        }
      } finally { thread.terminate(); }
    } else {
      for (let pass = 0; pass < 2; pass++) {
        const passStart = Date.now();
        const prediction = await ComicColorInference.predict(job, input, size.width, size.height, (): void => {}, report);
        write('output.bin', prediction.colors.buffer as ArrayBuffer);
        await delegator.print(`[ComicAcceleration] pass=${pass} backend=${prediction.backend} device=${prediction.deviceName} ` +
          `inference=${prediction.inferenceMs}ms total=${Date.now() - passStart}ms\n`);
        if (prediction.backend !== 'nnrt') throw new Error('NNRT not selected');
      }
    }
    await small.release(); await source.release(); await full.release();
    return;
  }
  let modelContext: mindSporeLite.Context = {
    target: ['cpu'], cpu: { threadNum: threads, precisionMode: precision }
  };
  if (backend === 'nnrt') {
    const devices = mindSporeLite.getAllNNRTDeviceDescriptions();
    const device = devices.find((item: mindSporeLite.NNRTDeviceDescription): boolean =>
      item.deviceType() === mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR);
    if (!device) throw new Error('No accelerator');
    modelContext = { target: ['nnrt', 'cpu'], cpu: { threadNum: threads, precisionMode: precision },
      nnrt: { deviceID: device.deviceID(), performanceMode: mindSporeLite.PerformanceMode.PERFORMANCE_HIGH } };
  }
  const model = await mindSporeLite.loadModelFromFile(modelPath, modelContext);
  const loaded = Date.now();
  await delegator.print(`[ComicEdge] backend=${backend} initial=${model.getInputs()[0].shape.join(',')} load=${loaded-started}ms\n`);
  if (model.getInputs()[0].shape.join(',') !== `1,${size.height},${size.width},5`) {
    if (!model.resize(model.getInputs(), [[1, size.height, size.width, 5]])) throw new Error('resize failed');
  }
  const inputs = model.getInputs();
  inputs[0].setData(input.buffer);
  const predictedAt = Date.now();
  const output = await model.predict(inputs);
  if (!output) throw new Error('predict returned undefined');
  await delegator.print(`[ComicEdge] output=${output[0].shape.join(',')}\n`);
  const predicted = Date.now();
  const colors = new Float32Array(output[0].getData());
  const owned = colors.slice();
  const planar = output[0].shape.join(',') === `1,3,${size.height},${size.width}`;
  if (planar) {
    const count = size.width * size.height;
    for (let i = 0; i < count; i++) {
      owned[i * 3] = colors[i]; owned[i * 3 + 1] = colors[count + i]; owned[i * 3 + 2] = colors[count * 2 + i];
    }
  }
  write('output.bin', owned.buffer as ArrayBuffer);
  const original = await full.createPixelMap({ desiredSize: ComicColorPixels.fit(info.size.width, info.size.height, 2048),
    desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
  const originalInfo = await original.getImageInfo();
  const originalBytes = new ArrayBuffer(original.getPixelBytesNumber());
  await original.readPixelsToBuffer(originalBytes);
  let changed = 0;
  if (!planar) for (let i = 0; i < colors.length; i++) if (colors[i] !== owned[i]) changed++;
  const blendAt = Date.now();
  const blended = ComicColorPixels.blend(new Uint8Array(originalBytes), originalInfo.size.width, originalInfo.size.height,
    original.getBytesNumberPerRow(), owned, input, smallInfo.size.width, smallInfo.size.height, size.width, size.height);
  const blendDone = Date.now();
  write('result.jpg', await ComicColorCodec.jpeg(blended, originalInfo.size));
  await delegator.print(`[ComicEdge] source=${info.size.width}x${info.size.height} small=${smallInfo.size.width}x${smallInfo.size.height} ` +
    `stride=${small.getBytesNumberPerRow()} model=${size.width}x${size.height} originalStride=${original.getBytesNumberPerRow()} ` +
    `load=${loaded-started}ms resize=${predictedAt-loaded}ms inference=${predicted-predictedAt}ms ` +
    `post=${Date.now()-predicted}ms blend=${blendDone-blendAt}ms mutated=${changed} precision=${precision}\n`);
  await small.release(); await original.release(); await source.release(); await full.release();
}
