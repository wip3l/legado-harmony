import { worker, MessageEvents } from '@kit.ArkTS';
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import image from '@ohos.multimedia.image';
import { ComicColorPixels } from '../core/reader/ComicColorPixels';
import { ComicColorCodec } from '../core/reader/ComicColorCodec';
import { ComicColorJob, ComicColorMessage } from '../core/reader/ComicColorTypes';

const port = worker.workerPort;
let cancelled: boolean = false;

function checkCancelled(): void {
  if (cancelled) throw new Error('已取消着色');
}

function progress(status: string): void {
  const message = new ComicColorMessage();
  message.status = status;
  port.postMessage(message);
}

async function run(job: ComicColorJob): Promise<ComicColorMessage> {
  const source = image.createImageSource(job.imageBytes);
  // Do not reuse an ImageSource after a reduced decode: some codecs retain its sampling state.
  const fullSource = image.createImageSource(job.imageBytes);
  let small: image.PixelMap | null = null;
  let original: image.PixelMap | null = null;
  try {
    const info = await source.getImageInfo();
    if (await source.getFrameCount() !== 1) throw new Error('暂不支持动图着色');
    checkCancelled();
    const inputSize = ComicColorPixels.modelSize(info.size.width, info.size.height);
    const modelSize = ComicColorPixels.padded(inputSize);
    const outputSize = ComicColorPixels.fit(info.size.width, info.size.height, 2048);
    progress('正在准备图片…');
    small = await source.createPixelMap({ desiredSize: inputSize, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    const decoded = await small.getImageInfo();
    if (decoded.pixelFormat !== image.PixelMapFormat.RGBA_8888) throw new Error('图片像素格式不支持');
    const bytes = new ArrayBuffer(small.getPixelBytesNumber());
    await small.readPixelsToBuffer(bytes);
    checkCancelled();
    const tensor = ComicColorPixels.input(new Uint8Array(bytes), decoded.size.width, decoded.size.height,
      small.getBytesNumberPerRow(), modelSize.width, modelSize.height);
    progress('正在加载本地着色模型…');
    const model = await mindSporeLite.loadModelFromFile(job.modelPath, {
      // Dynamic spatial conversion avoids stale fixed-size optimization data during resize.
      // FP16 execution is checked against ONNX at portrait and landscape sizes.
      target: ['cpu'], cpu: { threadNum: 4, precisionMode: 'preferred_fp16' }
    });
    checkCancelled();
    let inputs = model.getInputs();
    if (!model.resize(inputs, [[1, modelSize.height, modelSize.width, 5]])) throw new Error('着色模型尺寸调整失败');
    inputs = model.getInputs();
    if (inputs.length !== 1 || inputs[0].dtype !== mindSporeLite.DataType.NUMBER_TYPE_FLOAT32 ||
      inputs[0].shape.join(',') !== `1,${modelSize.height},${modelSize.width},5`) throw new Error('着色模型输入不匹配');
    inputs[0].setData(tensor.buffer);
    progress('正在本机着色…');
    const started = Date.now();
    const outputs = await model.predict(inputs);
    checkCancelled();
    const elapsed = Date.now() - started;
    if (outputs.length !== 1 || outputs[0].dtype !== mindSporeLite.DataType.NUMBER_TYPE_FLOAT32 ||
      outputs[0].shape.join(',') !== `1,3,${modelSize.height},${modelSize.width}`) throw new Error('着色模型输出不匹配');
    const colors = ComicColorPixels.interleave(new Float32Array(outputs[0].getData()), modelSize.width, modelSize.height);
    progress('正在保留线稿并合成彩色页面…');
    original = await fullSource.createPixelMap({ desiredSize: outputSize, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    const originalInfo = await original.getImageInfo();
    if (originalInfo.pixelFormat !== image.PixelMapFormat.RGBA_8888) throw new Error('图片像素格式不支持');
    const originalBytes = new ArrayBuffer(original.getPixelBytesNumber());
    await original.readPixelsToBuffer(originalBytes);
    checkCancelled();
    const rgba = ComicColorPixels.blend(new Uint8Array(originalBytes), originalInfo.size.width, originalInfo.size.height,
      original.getBytesNumberPerRow(), colors, tensor, decoded.size.width, decoded.size.height,
      modelSize.width, modelSize.height);
    const result = new ComicColorMessage();
    result.jpeg = await ComicColorCodec.jpeg(rgba, originalInfo.size);
    checkCancelled();
    result.width = originalInfo.size.width;
    result.height = originalInfo.size.height;
    result.inferenceMs = elapsed;
    return result;
  } finally {
    if (small) await small.release();
    if (original) await original.release();
    await source.release();
    await fullSource.release();
  }
}

port.onmessage = async (event: MessageEvents): Promise<void> => {
  const job = event.data as ComicColorJob;
  if (job.cancel) { cancelled = true; return; }
  try {
    const result = await run(job);
    port.postMessage(result, [result.jpeg]);
  } catch (error) {
    const message = new ComicColorMessage();
    message.error = (error as Error).message || '本机着色未完成，请重试';
    port.postMessage(message);
  }
};
