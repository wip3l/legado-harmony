import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const rawfile = new URL('../entry/src/main/resources/rawfile/opencc/', import.meta.url);
for (const [name, hash] of Object.entries({
  'LICENSE': 'b534e465949558eec2597b04f5092b5e161236a68dfbfd04d547592ac3964308',
  'TSCharacters.txt': '6b5a0a799bea2bb22c001f635eaa3fc2904310f0c08addbff275477a80ecf09a',
  'TSPhrases.txt': '504169029c43f7f234b8e2ae470720af3657675c5574ff8aa0feb257e1dc5ce2'
})) {
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(new URL(name, rawfile))).digest('hex'), hash);
}

const context = vm.createContext({ Map, Set, Number, Math, Error, Array, Infinity });
function load(file, sandbox) {
  const code = readEtsModule(file).replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, '');
  vm.runInContext(stripTypeScriptTypes(code, { mode: 'strip' }), sandbox);
}
load('core/reader/ComicTextTypes.ts', context);
load('core/reader/ComicChineseDictionary.ts', context);
load('core/reader/ComicTextRequests.ts', context);
const Requests = vm.runInContext('ComicTextRequests', context);
const firstRequest = Requests.put('data:image/png;base64,' + 'x'.repeat(200000));
assert.ok(firstRequest.length < 64);
assert.equal(Requests.take(firstRequest).length, 200022);
assert.equal(Requests.take(firstRequest), '', '路由交接后释放原始来源');
const oldest = Requests.put('old');
for (let index = 0; index < 4; index++) Requests.put(String(index));
assert.equal(Requests.take(oldest), '', '未打开的路由请求也有数量上限');
const Geometry = vm.runInContext('ComicTextGeometry', context);
const Dictionary = vm.runInContext('ComicChineseDictionary', context);
const converter = new Dictionary(fs.readFileSync(new URL('TSCharacters.txt', rawfile), 'utf8'),
  fs.readFileSync(new URL('TSPhrases.txt', rawfile), 'utf8'));
for (const [input, expected] of [
  ['繁體中文，漫畫閱讀。', '繁体中文，漫画阅读。'],
  ['乾坤大挪移，乾燥的頭髮。', '乾坤大挪移，干燥的头发。'],
  ['瞭望臺，一目瞭然。', '瞭望台，一目了然。'],
  ['Hello! 안녕하세요 😀\n123', 'Hello! 안녕하세요 😀\n123'],
  ['𠮷野家的麵條', '𠮷野家的面条'],
  ['', '']
]) assert.equal(converter.convert(input), expected, input);
assert.throws(() => new Dictionary('', ''), /字典/);

// 每个核心区完整覆盖原图且恰好覆盖一次，输入尺寸保持在可控范围。
for (const [width, height] of [[800, 1200], [1200, 18000], [3072, 9000], [32, 32000], [2048, 1280]]) {
  const tiles = Geometry.tiles(width, height);
  assert.equal(tiles[0].ownerTop, 0);
  assert.equal(tiles.at(-1).ownerBottom, height);
  for (let index = 0; index < tiles.length; index++) {
    const tile = tiles[index];
    assert.ok(tile.y <= tile.ownerTop);
    assert.ok(tile.y + tile.height >= tile.ownerBottom);
    assert.ok(tile.outputWidth <= 1536 && tile.outputHeight <= 1536);
    if (index) assert.equal(tile.ownerTop, tiles[index - 1].ownerBottom);
  }
}
for (const dimensions of [[0, 100], [100, NaN], [Infinity, 50], [20, 100], [10000, 10000], [32, 100000]]) {
  assert.throws(() => Geometry.tiles(...dimensions));
}
// 一句文字出现在两个重叠切片中时，只归属中心所在的核心区；保留原图坐标。
{
  const tiles = Geometry.tiles(1000, 3000);
  const original = [{ x: 100, y: 1270 }, { x: 500, y: 1270 }, { x: 500, y: 1310 }, { x: 100, y: 1310 }];
  const mapped = tiles.slice(0, 2).map((tile, index) => Geometry.mapLine(String(index), '同一句',
    original.map(p => ({ x: p.x * tile.outputWidth / 1000, y: (p.y - tile.y) * tile.outputHeight / tile.height })),
    tile, 1000, tile.outputWidth, tile.outputHeight));
  assert.equal(mapped[0], null);
  assert.ok(mapped[1]);
  assert.deepEqual(JSON.parse(JSON.stringify(mapped[1].points)), original);
  assert.equal(Geometry.mapLine('bad', 'text', [{ x: NaN, y: 1 }], tiles[0], 1000, 1000, 1000), null);
}

// 底色判断与文字层：纯色气泡可覆盖，网点背景不覆盖；只重写有变化的行，日文行不转换。
{
  const Sampler = vm.runInContext('ComicTextColorSampler', context);
  const Layer = vm.runInContext('ComicTextLayer', context);
  const width = 200, height = 120, stride = width * 4 + 16;
  const canvas = (background) => {
    const pixels = new Uint8Array(stride * height);
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
      const [r, g, b] = background(x, y);
      pixels.set([r, g, b, 255], y * stride + x * 4);
    }
    return pixels;
  };
  const ink = (pixels, left, top, right, bottom, color, bgra = false) => {
    for (let y = top; y < bottom; y++) for (let x = left; x < right; x++) {
      if ((x + y) % 3 === 0) continue; // 字形笔画只占一部分像素。
      pixels.set(bgra ? [color[2], color[1], color[0], 255] : [...color, 255], y * stride + x * 4);
    }
  };
  const box = [{ x: 40, y: 40 }, { x: 160, y: 40 }, { x: 160, y: 70 }, { x: 40, y: 70 }];
  const plain = canvas(() => [250, 248, 245]);
  ink(plain, 44, 44, 156, 66, [20, 30, 40]);
  const colors = Sampler.sample(plain, width, height, stride, false, box);
  assert.equal(colors.background, '#FAF8F5');
  assert.equal(colors.foreground, '#141E28');
  const swapped = canvas(() => [245, 248, 250]);
  ink(swapped, 44, 44, 156, 66, [20, 30, 40], true);
  assert.equal(Sampler.sample(swapped, width, height, stride, true, box).foreground, '#141E28', 'BGRA 通道顺序');
  const tone = canvas((x, y) => (x + y) % 4 < 2 ? [255, 255, 255] : [150, 150, 150]);
  ink(tone, 44, 44, 156, 66, [0, 0, 0]);
  assert.equal(Sampler.sample(tone, width, height, stride, false, box).background, '', '网点背景不覆盖');
  const scene = canvas((x) => [x, 255 - x, 128]);
  assert.equal(Sampler.sample(scene, width, height, stride, false, box).background, '', '渐变画面不覆盖');
  const behind = canvas(() => [255, 255, 255]);
  for (let y = 42; y < 68; y++) for (let x = 42; x < 158; x++) behind.set([128, 128, 128, 255], y * stride + x * 4);
  ink(behind, 44, 44, 156, 66, [0, 0, 0]);
  assert.equal(Sampler.sample(behind, width, height, stride, false, box).background, '', '字压在灰块上不覆盖');
  assert.equal(Sampler.sample(plain, width, height, width * 2, false, box).background, '', '步长异常');
  // 竖排对白：列宽 29、列距 9，OCR 框比字形各宽 3px；外圈会压到相邻列，应跳过其他行框后判为纯色。
  {
    const columns = canvas(() => [255, 255, 255]);
    const frames = [];
    for (let left = 20; left + 29 <= 180; left += 38) {
      ink(columns, left, 10, left + 29, 110, [0, 0, 0]);
      frames.push([{ x: left - 3, y: 7 }, { x: left + 32, y: 7 }, { x: left + 32, y: 113 }, { x: left - 3, y: 113 }]);
    }
    assert.equal(Sampler.sample(columns, width, height, stride, false, frames[1]).background, '', '不排除相邻列时被误判');
    for (const frame of frames) {
      assert.equal(Sampler.sample(columns, width, height, stride, false, frame, frames).background, '#FFFFFF',
        '密排竖列跳过相邻行框后可覆盖');
    }
  }
  assert.equal(Sampler.sample(plain, width, height, stride, false, box.slice(0, 3)).background, '');
  // 贴着气泡边线的列：外圈压到边线判不出底色，借相邻列的底色后只靠框内检查；框内是网点时仍不覆盖。
  {
    const edge = canvas((x) => x >= 14 && x <= 16 ? [0, 0, 0] : [255, 255, 255]);
    ink(edge, 20, 10, 46, 110, [0, 0, 0]);
    ink(edge, 60, 10, 86, 110, [0, 0, 0]);
    const lines = [
      [{ x: 18, y: 8 }, { x: 48, y: 8 }, { x: 48, y: 112 }, { x: 18, y: 112 }],
      [{ x: 58, y: 8 }, { x: 88, y: 8 }, { x: 88, y: 112 }, { x: 58, y: 112 }],
      [{ x: 150, y: 8 }, { x: 180, y: 8 }, { x: 180, y: 112 }, { x: 150, y: 112 }]
    ];
    const first = lines.map((line) => Sampler.sample(edge, width, height, stride, false, line, lines).background);
    assert.deepEqual(Array.from(first), ['', '#FFFFFF', ''], '贴边列判不出；第三框没有笔画也不算');
    assert.equal(Sampler.neighborBackground(0, lines, first), '#FFFFFF', '取间隔不超过字宽 1.5 倍的最近一行');
    assert.equal(Sampler.neighborBackground(0, lines, ['', '', '#FFFFFF']), '', '隔得远的行不借');
    assert.equal(Sampler.sample(edge, width, height, stride, false, lines[0], lines, '#FFFFFF').background, '#FFFFFF',
      '借用底色后可覆盖');
    const toned = canvas((x, y) => x >= 14 && x <= 16 ? [0, 0, 0] : ((x + y) % 4 < 2 ? [255, 255, 255] : [150, 150, 150]));
    ink(toned, 20, 10, 46, 110, [0, 0, 0]);
    assert.equal(Sampler.sample(toned, width, height, stride, false, lines[0], lines, '#FFFFFF').background, '',
      '借来的底色仍要过框内检查');
  }

  const region = (id, group, text, x, y, w, h, background = '#FFFFFF') => ({
    id, group, text, background, foreground: '#000000',
    points: [{ x, y }, { x: x + w, y }, { x: x + w, y: y + h }, { x, y: y + h }]
  });
  const layer = Layer.build({ width: 1000, height: 2000, regions: [
    region('a', 'g1', '這是', 100, 100, 40, 80),
    region('b', 'g1', '漫畫', 150, 100, 40, 80),
    region('c', 'g2', '一樣的字', 300, 300, 200, 40, ''),
    region('d', 'g3', 'すごい漫畫', 300, 400, 200, 40),
    region('e', 'g4', 'Hello', 300, 500, 200, 40),
    region('f', 'g5', '頭髮', 0, 0, 3, 40),
    // OCR 把竖排破折号认成长音符、着重点认成间隔号：仍是中文，要转换。
    region('k', 'g6', '很容易壞掉耶ー。', 600, 100, 40, 300),
    region('m', 'g7', '眞・的', 700, 100, 40, 120)
  ] }, (text) => converter.convert(text));
  assert.deepEqual(Array.from(layer.patches, p => p.id), ['a', 'b', 'k', 'm'], '只重写有变化且可覆盖的行');
  assert.equal(layer.patches[2].text, Array.from('很容易坏掉耶ー。').join('\n'));
  assert.equal(layer.skipped, 2, '底色不纯或过小的行计为跳过');
  const [first, second] = layer.patches;
  assert.equal(first.text, '这\n是');
  assert.equal(first.vertical, true);
  assert.equal(second.text, '漫\n画');
  assert.equal(first.lines, 2);
  assert.ok(first.x < 100 && first.y < 100 && first.x + first.width > 140, '外扩盖住原字边缘');
  assert.ok(first.fontSize > 20 && first.fontSize <= 40);
  const across = Layer.build({ width: 1000, height: 1000, regions: [
    region('x', 'g', '頭', 100, 100, 40, 40), region('y', 'g', '髮', 100, 150, 40, 40)
  ] }, (text) => converter.convert(text));
  assert.deepEqual(Array.from(across.patches, p => p.text), ['头', '发'], '跨行词组整块转换后按原行切回');
  const horizontal = Layer.build({ width: 1000, height: 1000, regions: [region('h', '', '繁體中文', 10, 10, 200, 40)] },
    (text) => converter.convert(text)).patches[0];
  assert.equal(horizontal.vertical, false);
  assert.equal(horizontal.text, '繁体中文');
  assert.ok(horizontal.x >= 0 && horizontal.y >= 0);
}

// 执行实际 OCR 适配代码，替身只模拟系统和文件 API；不把这项检查当作真机 OCR 效果测试。
const files = new Map([['/input/a.png', Buffer.from('original-a')]]);
const handles = new Map();
let nextFd = 0, ocrCalls = 0, inits = 0, releases = 0, pixelReleases = 0, imageReleases = 0, downloads = 0;
let imageHeight = 1800, failOcr = false, failCache = false, failPixels = false, gate = null, mtime = 1;
let capability = true;
const timers = [];
const budget = { writes: 0, hits: 0 };
const sandbox = vm.createContext({
  console, Map, Set, Promise, Error, Date, Number, Math, ArrayBuffer, Uint8Array, Infinity, Array,
  setTimeout: (callback) => { timers.push(callback); return timers.length; },
  clearTimeout: (id) => { timers[id - 1] = null; },
  canIUse: () => capability,
  deviceInfo: { osFullName: 'test-os-1' },
  digestHashHex: (algorithm, value) => crypto.createHash('sha256').update(value).digest('hex'),
  util: { Base64Helper: class { decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); } } },
  fileUri: { FileUri: class { constructor(value) { this.path = value.replace('file://', ''); } } },
  fs: {
    OpenMode: { READ_ONLY: 1, CREATE: 2, WRITE_ONLY: 4, TRUNC: 8 },
    accessSync: path => files.has(path), mkdirSync() {},
    statSync(path) {
      if (!files.has(path)) throw new Error('ENOENT');
      return { size: files.get(path).length, mtime, isFile: () => true };
    },
    async stat(path) { return this.statSync(path); },
    openSync(path, mode) {
      if (mode !== 1 && failCache) throw new Error('disk full');
      if (mode === 1 && !files.has(path)) throw new Error('ENOENT');
      if (mode !== 1) files.set(path, Buffer.alloc(0));
      const fd = ++nextFd; handles.set(fd, { path }); return { fd };
    },
    closeSync(file) { handles.delete(typeof file === 'number' ? file : file.fd); },
    readTextSync(path) { if (!files.has(path)) throw new Error('ENOENT'); return files.get(path).toString(); },
    writeSync(fd, data) { files.set(handles.get(fd).path, Buffer.from(data)); },
    renameSync(source, target) { files.set(target, files.get(source)); files.delete(source); },
    unlinkSync(path) { files.delete(path); }
  },
  ReaderComicImageExport: { async downloadImage() { downloads++; return new Uint8Array(Buffer.from('remote-image')); } },
  ReaderCacheBudget: { touchComicFile() { budget.hits++; }, noteComicWrite() { budget.writes++; } },
  image: {
    CropAndScaleStrategy: { CROP_FIRST: 2 }, PixelMapFormat: { RGBA_8888: 3, BGRA_8888: 4 },
    createImageSource() { return {
      async getImageInfo() { return { size: { width: 1000, height: imageHeight } }; },
      async createPixelMap(options) {
        const { width, height } = options.desiredSize;
        return {
          options,
          async getImageInfo() { return { size: options.desiredSize, pixelFormat: 3 }; },
          getPixelBytesNumber: () => width * height * 4,
          getBytesNumberPerRow: () => width * 4,
          async readPixelsToBuffer(buffer) {
            if (failPixels) throw new Error('read failed');
            const view = new Uint8Array(buffer);
            view.fill(255);
            // 识别替身返回的行框里画黑字。
            const y0 = options.desiredRegion.y > 0 ? 200 : 100;
            for (let y = y0 + 2; y < y0 + 18; y++) for (let x = 12; x < 88; x += 2) view.set([0, 0, 0, 255], (y * width + x) * 4);
          },
          async release() { pixelReleases++; }
        };
      },
      async release() { imageReleases++; }
    }; }
  },
  textRecognition: {
    async init() { inits++; return true; }, async getSupportedLanguages() { return ['zh-TW', 'ja', 'en', 'ko']; },
    async release() { releases++; },
    async recognizeText({pixelMap}) {
      ocrCalls++;
      if (gate) await gate;
      if (failOcr) throw new Error('service error');
      const y = pixelMap.options.desiredRegion.y > 0 ? 200 : 100;
      return { blocks: [{ lines: [{ value: '漫畫文字', cornerPoints: [
        {x: 10, y}, {x: 90, y}, {x: 90, y: y + 20}, {x: 10, y: y + 20}
      ] }] }] };
    }
  }
});
load('core/reader/ComicTextTypes.ts', sandbox);
load('core/reader/ComicTextRecognizer.ets', sandbox);
const Recognizer = vm.runInContext('ComicTextRecognizer', sandbox);
const app = { cacheDir: '/cache' };
const fireTimers = async () => {
  for (const timer of timers.splice(0)) if (timer) timer();
  await new Promise(resolve => setTimeout(resolve, 5));
};
const progress = [];
const result = await Recognizer.recognize(app, 'file:///input/a.png', () => true, (done, total) => progress.push([done, total]));
assert.equal(result.regions.length, 2);
assert.match(result.imageHash, /^[0-9a-f]{64}$/);
assert.equal(result.regions[0].group, '0_b0');
assert.equal(result.regions[0].background, '#FFFFFF', '识别时记录底色');
assert.equal(result.regions[0].foreground, '#000000');
assert.equal(ocrCalls, 2);
assert.equal(pixelReleases, 2);
assert.equal(imageReleases, 1);
assert.equal(handles.size, 0, '本地文件句柄已关闭');
assert.equal(downloads, 0, '本地图不得触发网络下载');
assert.deepEqual(progress.at(-1), [2, 2]);
const cache = [...files.keys()].find(key => key.endsWith('.json'));
assert.match(cache, /^\/cache\/comic_images\/ocr_v4_/);
await Recognizer.recognize(app, '/input/a.png', () => true, () => {});
assert.equal(ocrCalls, 2, '重复识别复用缓存');
assert.equal(budget.hits, 1);
assert.equal(inits, 1, '连续识别复用系统服务');
assert.equal(releases, 0);
await fireTimers();
assert.equal(releases, 1, '空闲后释放系统服务');
files.set(cache, Buffer.from('{bad json'));
await Recognizer.recognize(app, '/input/a.png', () => true, () => {});
assert.equal(ocrCalls, 4, '损坏缓存应重新识别');
assert.equal(inits, 2, '释放后重新初始化');
sandbox.deviceInfo.osFullName = 'test-os-2';
await Recognizer.recognize(app, '/input/a.png', () => true, () => {});
assert.equal(ocrCalls, 6, '系统升级后重新识别');
mtime = 2;
await Recognizer.recognize(app, '/input/a.png', () => true, () => {});
assert.equal(ocrCalls, 8, '文件变化后重新识别');
await Recognizer.recognize(app, 'https://example.com/1.jpg', () => true, () => {});
await Recognizer.recognize(app, 'https://example.com/1.jpg', () => true, () => {});
assert.equal(downloads, 1, '网络图命中缓存后不再下载');

// 取消正在执行的任务；排队中已取消的任务不得启动 OCR；取消不释放服务，服务出错才释放；后续重试正常。
let unlock;
gate = new Promise(resolve => { unlock = resolve; });
let active = true;
const callsBefore = ocrCalls;
const running = Recognizer.recognize(app, '/input/a.png', () => active, () => {}, true);
while (ocrCalls < callsBefore + 1) await new Promise(resolve => setTimeout(resolve, 1));
const skipped = Recognizer.recognize(app, '/input/a.png', () => false, () => {}, true);
active = false;
unlock();
await assert.rejects(running, /取消/);
await assert.rejects(skipped, /取消/);
gate = null;
assert.equal(ocrCalls, callsBefore + 1);
assert.equal(handles.size, 0);
const releasesBefore = releases;
failOcr = true;
await assert.rejects(Recognizer.recognize(app, '/input/a.png', () => true, () => {}, true), /service error/);
assert.equal(releases, releasesBefore + 1, '服务出错后释放');
failOcr = false;
failCache = true;
failPixels = true;
const recovered = await Recognizer.recognize(app, '/input/a.png', () => true, () => {}, true);
assert.equal(recovered.regions.length, 2, '缓存写失败、读不到像素仍返回识别结果');
assert.equal(recovered.regions[0].background, '', '读不到像素时不覆盖');
failCache = false;
failPixels = false;
await fireTimers();
assert.equal(inits, releases, '所有初始化的服务均释放');
assert.equal(handles.size, 0);
capability = false;
await assert.rejects(Recognizer.recognize(app, '/input/a.png', () => true, () => {}), /不支持/);
capability = true;

// 长按入口交接短路由 ID，不改变原有保存/分享/刷新按钮索引；加载中的图片不能送去 OCR。
let menuIndex = 3, routed = null, saved = 0, shared = 0, reloaded = 0, toast = '';
const menuContext = vm.createContext({
  Map, Set, Error,
  router: { async pushUrl(options) { routed = options; } },
  HdsFeedback: { showToast(value) { toast = value; } },
  ReaderImageMarker: { pendingRaw: value => value === 'pending' ? 'raw' : '', failureReason: () => '' },
  ReaderImageResults: { current: () => '' },
  ReaderComicImageExport: {
    async saveToAlbum() { saved++; return true; }, async share() { shared++; }
  }
});
load('core/reader/ComicTextRequests.ts', menuContext);
load('core/reader/ReaderComicImageActions.ets', menuContext);
const Actions = vm.runInContext('ReaderComicImageActions', menuContext);
const MenuRequests = vm.runInContext('ComicTextRequests', menuContext);
const actions = new Actions({
  uiContext: () => ({ getPromptAction: () => ({ async showActionMenu() { return { index: menuIndex }; } }) }),
  abilityContext: () => ({}), accentColor: () => '#007DFF',
  isLocalBook: () => true, currentChapter: () => 0, busy: () => false, refreshCurrentChapter() {}
});
await actions.showMenu('/input/a.png', () => reloaded++, '');
assert.equal(routed.url, 'pages/ComicText');
assert.equal(MenuRequests.take(routed.params.requestId), '/input/a.png');
assert.equal(routed.params.source, undefined);
for (menuIndex of [0, 1, 2]) await actions.showMenu('/input/a.png', () => reloaded++, '');
assert.deepEqual([saved, shared, reloaded], [1, 1, 1]);
routed = null;
menuIndex = 3;
await actions.showMenu('pending', () => reloaded++, '');
assert.equal(routed, null);
assert.equal(toast, '图片还在加载');
console.log('comic-text-check: passed (dictionary, geometry, colors, text layer, cache, engine reuse, cancellation, cleanup, reader menu)');
